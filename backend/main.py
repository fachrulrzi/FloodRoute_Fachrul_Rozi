
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field
import httpx
import math
import logging

# ============================================================
# KONFIGURASI APLIKASI
# ============================================================

app = FastAPI(
    title="FloodRoute Backend",
    version="2.1.0",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)

FIREBASE_URL = (
    "https://data-banjir-87a89-default-rtdb.firebaseio.com"
)
GRAPHHOPPER_URL = "http://localhost:8989"

REQUEST_TIMEOUT = 30.0

FLOOD_THRESHOLD_CM = 30.0
WARNING_THRESHOLD_CM = 20.0

FLOOD_SEGMENT_LENGTH_M = 60.0
DEFAULT_ROAD_WIDTH_M = 3.5

# Bearing 90 derajat berarti ruas memanjang ke arah timur-barat.
DEFAULT_BEARING_DEG = 90.0

# Margin tambahan di kedua sisi poligon untuk toleransi
# ketidakakuratan koordinat dan geometri jalan.
FLOOD_BUFFER_M = 2.0

EARTH_RADIUS_M = 6_371_000.0

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("floodroute")


# ============================================================
# MODEL REQUEST
# ============================================================

class Location(BaseModel):
    latitude: float = Field(ge=-90, le=90)
    longitude: float = Field(ge=-180, le=180)


class RouteRequest(BaseModel):
    origin: Location
    destination: Location
    vehicle: str = "car"


# ============================================================
# ENDPOINT INFORMASI
# ============================================================

@app.get("/")
async def root():
    return {
        "status": "FloodRoute Backend aktif",
        "firebase": FIREBASE_URL,
        "graphhopper": GRAPHHOPPER_URL,
        "flood_threshold_cm": FLOOD_THRESHOLD_CM,
        "warning_threshold_cm": WARNING_THRESHOLD_CM,
        "polygon_length_m": FLOOD_SEGMENT_LENGTH_M,
        "polygon_buffer_m": FLOOD_BUFFER_M,
    }


# ============================================================
# MENGAMBIL DATA SENSOR FIREBASE
# ============================================================

async def fetch_sensors():
    try:
        async with httpx.AsyncClient(timeout=10.0) as client:
            response = await client.get(
                f"{FIREBASE_URL}/sensors.json"
            )
            response.raise_for_status()
            data = response.json()

    except httpx.HTTPError as exc:
        logger.exception("Permintaan Firebase gagal")

        raise HTTPException(
            status_code=502,
            detail=f"Gagal mengambil data Firebase: {exc}",
        ) from exc

    if not isinstance(data, dict):
        return []

    sensors = []

    for key, item in data.items():
        if not isinstance(item, dict):
            continue

        # Sesuaikan dengan struktur data Firebase.
        try:
            lat = float(item["lat"])
            lon = float(item["lon"])
            level = float(item.get("level_cm", 0))

            if not (
                math.isfinite(lat)
                and math.isfinite(lon)
                and math.isfinite(level)
            ):
                raise ValueError("Nilai sensor bukan angka valid")

            if not (-90 <= lat <= 90):
                raise ValueError("Latitude di luar rentang")

            if not (-180 <= lon <= 180):
                raise ValueError("Longitude di luar rentang")

        except (KeyError, TypeError, ValueError) as exc:
            logger.warning(
                "Data sensor %s dilewati: %s",
                key,
                exc,
            )
            continue

        raw_status = str(
            item.get("status", "normal")
        ).strip().lower()

        if (
            level >= FLOOD_THRESHOLD_CM
            or raw_status in {"banjir", "flood", "flooded"}
        ):
            status = "flooded"

        elif (
            level >= WARNING_THRESHOLD_CM
            or raw_status in {"waspada", "warning"}
        ):
            status = "warning"

        else:
            status = "normal"

        try:
            road_width = float(
                item.get(
                    "road_width_m",
                    DEFAULT_ROAD_WIDTH_M,
                )
            )

            if not math.isfinite(road_width):
                raise ValueError("Lebar jalan tidak valid")

        except (TypeError, ValueError):
            road_width = DEFAULT_ROAD_WIDTH_M

        road_width = min(max(road_width, 3.0), 40.0)

        try:
            bearing = float(
                item.get(
                    "bearing_deg",
                    DEFAULT_BEARING_DEG,
                )
            )

            if not math.isfinite(bearing):
                raise ValueError("Bearing tidak valid")

        except (TypeError, ValueError):
            bearing = DEFAULT_BEARING_DEG

        sensors.append({
            "sensor_id": str(item.get("sensor_id", key)),
            "location_name": str(
                item.get("location_name", key)
            ),
            "latitude": lat,
            "longitude": lon,
            "level_cm": level,
            "status": status,
            "road_width_m": road_width,
            "bearing_deg": bearing % 360.0,
            "timestamp": item.get("timestamp"),
        })

    logger.info(
        "Data sensor terbaca: %d, sensor banjir: %d",
        len(sensors),
        sum(s["status"] == "flooded" for s in sensors),
    )

    return sensors


# ============================================================
# STATUS BANJIR
# ============================================================

@app.get("/flood")
async def flood_status():
    sensors = await fetch_sensors()

    return {
        "count": len(sensors),
        "flooded_count": sum(
            s["status"] == "flooded" for s in sensors
        ),
        "warning_count": sum(
            s["status"] == "warning" for s in sensors
        ),
        "sensors": sensors,
    }


# ============================================================
# PERHITUNGAN KOORDINAT
# ============================================================

def xy_to_latlon(x_m, y_m, ref_lat, ref_lon):
    lat = ref_lat + math.degrees(
        y_m / EARTH_RADIUS_M
    )

    cos_lat = max(
        abs(math.cos(math.radians(ref_lat))),
        1e-10,
    )

    lon = ref_lon + math.degrees(
        x_m / (EARTH_RADIUS_M * cos_lat)
    )

    return lat, lon


# ============================================================
# MEMBUAT POLIGON BANJIR
# ============================================================

def create_polygon(sensor):
    """
    Menghasilkan poligon perkiraan area banjir.

    GeoJSON menggunakan urutan koordinat:
    [longitude, latitude].

    Bearing 0 derajat  : utara-selatan.
    Bearing 90 derajat : timur-barat.

    Buffer ditambahkan pada kedua sisi lebar jalan.
    """

    bearing = math.radians(sensor["bearing_deg"])

    along_x = math.sin(bearing)
    along_y = math.cos(bearing)

    across_x = math.cos(bearing)
    across_y = -math.sin(bearing)

    half_length = FLOOD_SEGMENT_LENGTH_M / 2.0

    half_width = (
        sensor["road_width_m"] / 2.0
        + FLOOD_BUFFER_M
    )

    ring = []

    corners = [
        (-1, -1),
        (1, -1),
        (1, 1),
        (-1, 1),
        (-1, -1),
    ]

    for along_sign, across_sign in corners:
        x = (
            along_sign * half_length * along_x
            + across_sign * half_width * across_x
        )

        y = (
            along_sign * half_length * along_y
            + across_sign * half_width * across_y
        )

        lat, lon = xy_to_latlon(
            x,
            y,
            sensor["latitude"],
            sensor["longitude"],
        )

        ring.append([lon, lat])

    return ring


# ============================================================
# MEMBANGUN GEOJSON DAN AREA BERNAMA
# ============================================================

def build_areas(flooded_sensors):
    features = []
    polygons = []
    named_areas = {}

    for index, sensor in enumerate(flooded_sensors):
        ring = create_polygon(sensor)

        area_id = f"flood_{index}"

        feature = {
            "type": "Feature",
            "id": area_id,
            "properties": {
                "sensor_id": sensor["sensor_id"],
                "location_name": sensor["location_name"],
                "water_level_cm": sensor["level_cm"],
            },
            "geometry": {
                "type": "Polygon",
                "coordinates": [ring],
            },
        }

        features.append(feature)

        # Pemetaan nama area yang digunakan dalam Custom Model.
        named_areas[area_id] = {
            "type": "Feature",
            "geometry": feature["geometry"],
            "properties": feature["properties"],
        }

        polygons.append({
            "name": sensor["location_name"],
            "area_id": area_id,
            "ring": ring,
        })

        logger.info(
            "POLIGON %s: sensor=(%.6f, %.6f), "
            "level=%.2f cm, bearing=%.1f, ring=%s",
            sensor["location_name"],
            sensor["latitude"],
            sensor["longitude"],
            sensor["level_cm"],
            sensor["bearing_deg"],
            ring,
        )

    geojson = {
        "type": "FeatureCollection",
        "features": features,
    }

    return geojson, named_areas, polygons


# ============================================================
# VALIDASI TITIK TERHADAP POLIGON
# ============================================================

def point_in_polygon(lat, lon, ring):
    """
    Ray-casting test.

    ring berformat:
    [[longitude, latitude], ...]
    """

    x = lon
    y = lat

    inside = False
    j = len(ring) - 1

    for i, (xi, yi) in enumerate(ring):
        xj, yj = ring[j]

        if (yi > y) != (yj > y):
            cross_x = (
                (xj - xi) * (y - yi)
                / ((yj - yi) or 1e-15)
                + xi
            )

            if x < cross_x:
                inside = not inside

        j = i

    return inside


# ============================================================
# JARAK ANTAR TITIK
# ============================================================

def haversine_m(lat1, lon1, lat2, lon2):
    p1 = math.radians(lat1)
    p2 = math.radians(lat2)

    dlat = math.radians(lat2 - lat1)
    dlon = math.radians(lon2 - lon1)

    a = (
        math.sin(dlat / 2) ** 2
        + math.cos(p1)
        * math.cos(p2)
        * math.sin(dlon / 2) ** 2
    )

    a = min(1.0, max(0.0, a))

    return (
        2
        * EARTH_RADIUS_M
        * math.asin(math.sqrt(a))
    )


# ============================================================
# VALIDASI SELURUH GEOMETRI RUTE
# ============================================================

def find_intersections(coordinates, polygons, step_m=2.0):
    """
    Memeriksa titik-titik di sepanjang rute dengan
    interval maksimum sekitar 2 meter.

    Mengembalikan seluruh nama poligon yang terdeteksi
    berpotongan dengan rute.
    """

    if not coordinates:
        return []

    intersected = set()

    if len(coordinates) == 1:
        lon, lat = coordinates[0][:2]

        for polygon in polygons:
            if point_in_polygon(
                lat,
                lon,
                polygon["ring"],
            ):
                intersected.add(polygon["name"])

        return sorted(intersected)

    for index in range(len(coordinates) - 1):
        lon1, lat1 = coordinates[index][:2]
        lon2, lat2 = coordinates[index + 1][:2]

        segment_length = haversine_m(
            lat1,
            lon1,
            lat2,
            lon2,
        )

        steps = max(
            1,
            math.ceil(segment_length / step_m),
        )

        for step in range(steps + 1):
            fraction = step / steps

            lat = lat1 + (lat2 - lat1) * fraction
            lon = lon1 + (lon2 - lon1) * fraction

            for polygon in polygons:
                if polygon["name"] in intersected:
                    continue

                if point_in_polygon(
                    lat,
                    lon,
                    polygon["ring"],
                ):
                    intersected.add(polygon["name"])

    return sorted(intersected)


# ============================================================
# MEMBACA ERROR GRAPHHOPPER
# ============================================================

def graphhopper_error(response):
    try:
        body = response.json()

        return str(
            body.get("message")
            or body.get("hints")
            or body
        )

    except ValueError:
        return response.text[:2000]


async def request_graphhopper(client, body):
    """
    Mengirim satu permintaan ke GraphHopper.
    Error koneksi ditangani terpisah dari error routing.
    """

    try:
        response = await client.post(
            f"{GRAPHHOPPER_URL}/route",
            json=body,
        )

    except httpx.HTTPError as exc:
        logger.exception("GraphHopper tidak dapat dihubungi")

        raise HTTPException(
            status_code=502,
            detail={
                "error_code": "GRAPHHOPPER_CONNECTION_FAILED",
                "message": "GraphHopper tidak dapat dihubungi.",
                "reason": str(exc),
            },
        ) from exc

    if response.status_code != 200:
        detail = graphhopper_error(response)

        logger.error(
            "GraphHopper gagal: status=%s, response=%s",
            response.status_code,
            response.text[:2000],
        )

        raise HTTPException(
            status_code=502,
            detail={
                "error_code": "GRAPHHOPPER_ROUTING_FAILED",
                "message": "GraphHopper gagal menghitung rute.",
                "graphhopper_status": response.status_code,
                "graphhopper_detail": detail,
            },
        )

    try:
        result = response.json()

    except ValueError as exc:
        raise HTTPException(
            status_code=502,
            detail="Respons GraphHopper bukan JSON yang valid.",
        ) from exc

    return result


# ============================================================
# ENDPOINT UTAMA ROUTING
# ============================================================

@app.post("/route")
async def calculate_route(request: RouteRequest):
    vehicle = request.vehicle.strip().lower()

    profile = (
        "motorcycle"
        if vehicle in {"motor", "motorcycle", "motorbike"}
        else "car"
    )

    base_body = {
        "points": [
            [
                request.origin.longitude,
                request.origin.latitude,
            ],
            [
                request.destination.longitude,
                request.destination.latitude,
            ],
        ],
        "profile": profile,
        "points_encoded": False,
        "instructions": False,
        "ch.disable": True,
    }

    # Satu snapshot sensor untuk seluruh proses routing.
    sensors = await fetch_sensors()

    flooded = [
        sensor
        for sensor in sensors
        if sensor["status"] == "flooded"
    ]

    logger.info(
        "Permintaan routing: profile=%s, sensor_banjir=%d",
        profile,
        len(flooded),
    )

    async with httpx.AsyncClient(
        timeout=REQUEST_TIMEOUT
    ) as client:

        # ----------------------------------------------------
        # JIKA TIDAK ADA SENSOR BANJIR
        # ----------------------------------------------------

        if not flooded:
            result = await request_graphhopper(
                client,
                base_body,
            )

            result["floodroute"] = {
                "mode": "normal",
                "flooded_sensor_count": 0,
                "message": (
                    "Tidak ada sensor berstatus banjir; "
                    "rute normal ditampilkan."
                ),
            }

            return result

        # ----------------------------------------------------
        # BANGUN AREA BANJIR
        # ----------------------------------------------------

        geojson, named_areas, polygons = build_areas(
            flooded
        )

        logger.info(
            "Jumlah area banjir yang dikirim ke GraphHopper: %d",
            len(named_areas),
        )

        # ----------------------------------------------------
        # CUSTOM MODEL UNTUK MENGHINDARI BANJIR
        # ----------------------------------------------------

        custom_model = {
            "distance_influence": 100,
            "areas": named_areas,

            # Penalti prioritas sangat besar untuk ruas
            # yang berada dalam area banjir.
            "priority": [
                {
                    "if": f"in_{area_id}",
                    "multiply_by": 0.001,
                }
                for area_id in named_areas
            ],

            # Turunkan kecepatan secara signifikan pada area
            # banjir sebagai penalti tambahan.
            "speed": [
                {
                    "if": f"in_{area_id}",
                    "multiply_by": 0.1,
                }
                for area_id in named_areas
            ],
        }

        request_body = {
            **base_body,
            "custom_model": custom_model,
        }

        # ----------------------------------------------------
        # HITUNG RUTE DENGAN PENGHINDARAN BANJIR
        # ----------------------------------------------------

        result = await request_graphhopper(
            client,
            request_body,
        )

        paths = result.get("paths") or []

        if not paths:
            raise HTTPException(
                status_code=502,
                detail={
                    "error_code": "EMPTY_ROUTE",
                    "message": (
                        "GraphHopper tidak mengembalikan "
                        "jalur yang dapat digunakan."
                    ),
                },
            )

        coordinates = (
            (paths[0].get("points") or {}).get("coordinates")
            or []
        )

        # ----------------------------------------------------
        # VALIDASI HASIL RUTE
        # ----------------------------------------------------

        intersected = find_intersections(
            coordinates,
            polygons,
            step_m=2.0,
        )

        if intersected:
            logger.warning(
                "Rute masih berpotongan dengan area banjir: %s",
                intersected,
            )

            raise HTTPException(
                status_code=409,
                detail={
                    "error_code": "NO_VERIFIED_SAFE_ROUTE",
                    "message": (
                        "Rute hasil GraphHopper masih "
                        "berpotongan dengan poligon banjir. "
                        "Rute tidak dinyatakan aman."
                    ),
                    "intersected_areas": intersected,
                    "flooded_sensor_count": len(flooded),
                    "suggestion": (
                        "Periksa posisi sensor, bearing, "
                        "lebar dan panjang poligon, serta "
                        "penerapan Custom Model GraphHopper."
                    ),
                },
            )

        # ----------------------------------------------------
        # RUTE LOLOS VALIDASI POLIGON
        # ----------------------------------------------------

        result["floodroute"] = {
            "mode": "flood_avoidance_validated",
            "flooded_sensor_count": len(flooded),
            "validated": True,
            "message": (
                "Rute tidak berpotongan dengan poligon "
                "banjir yang terdeteksi."
            ),
            "note": (
                "Validasi berdasarkan poligon perkiraan "
                "dari data sensor, bukan jaminan kondisi "
                "jalan nyata bebas banjir."
            ),
            "areas": [
                {
                    "sensor_id": sensor["sensor_id"],
                    "location_name": sensor["location_name"],
                    "level_cm": sensor["level_cm"],
                }
                for sensor in flooded
            ],
        }

        logger.info(
            "Rute lolos validasi poligon banjir."
        )

        return result
