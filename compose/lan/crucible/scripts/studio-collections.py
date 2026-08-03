#!/usr/bin/env python3
"""
Smart Collections for Jellyfin
Creates and maintains collections based on studios, franchises, and genres.
Fetches poster art from TMDb.
Runs daily on cron -- automatically picks up new movies.
"""

import json
import urllib.request
import urllib.parse
import time
import os

JF_URL = "http://10.1.0.52:8096"
# secrets from /opt/yams/scripts/.env (mode 600, gitignored) so this file can
# live in git. note this uses a DIFFERENT jellyfin key than tunarr-sync.
JF_KEY = os.environ["STUDIO_JF_KEY"]
TMDB_KEY = os.environ["TMDB_KEY"]
TMDB_IMG = "https://image.tmdb.org/t/p/original"
POSTER_CACHE = "/opt/yams/config/collection-posters"

# ── Studio Collections ────────────────────────────────────────
STUDIO_COLLECTIONS = {
    "Marvel": ["Marvel Studios", "Marvel Entertainment", "Kevin Feige Productions"],
    "Pixar": ["Pixar"],
    "Disney": ["Walt Disney Pictures", "Walt Disney Animation Studios"],
    "Studio Ghibli": ["Studio Ghibli"],
    "A24": ["A24"],
    "DC": ["DC Films", "DC Entertainment", "DC Studios", "DC Comics"],
    "DreamWorks": ["DreamWorks Animation", "DreamWorks Pictures"],
    "Lucasfilm": ["Lucasfilm Ltd."],
    "James Bond": ["EON Productions"],
    "Harry Potter": ["Heyday Films"],
    "Christopher Nolan": ["Syncopy"],
}

# ── Franchise Collections (match by movie title keywords) ─────
FRANCHISE_COLLECTIONS = {
    "Spider-Man": ["Spider-Man", "Amazing Spider-Man", "Spider-Verse"],
    "Mission: Impossible": ["Mission: Impossible"],
    "Transformers": ["Transformers"],
    "X-Men": ["X-Men", "X2", "Dark Phoenix", "Deadpool"],
    "Jason Bourne": ["Bourne"],
    "Pirates of the Caribbean": ["Pirates of the Caribbean"],
    "Knives Out": ["Knives Out", "Glass Onion", "Wake Up Dead Man"],
    "Kingsman": ["Kingsman", "King's Man"],
    "Star Trek": ["Star Trek"],
    "Toy Story": ["Toy Story"],
    "Tron": ["Tron", "TRON"],
    "John Wick": ["John Wick"],
    "Kung Fu Panda": ["Kung Fu Panda"],
    "The Twilight Saga": ["Twilight", "Breaking Dawn", "New Moon", "Eclipse"],
    "Cars": ["Cars"],
    "Frozen": ["Frozen"],
    "Finding Nemo": ["Finding Nemo", "Finding Dory"],
    "Monsters, Inc.": ["Monsters, Inc.", "Monsters University"],
    "The Incredibles": ["Incredibles"],
    "Fifty Shades": ["Fifty Shades"],
}

# ── Genre Collections ─────────────────────────────────────────
GENRE_COLLECTIONS = {
    "Animation": ["Animation"],
    "Sci-Fi": ["Science Fiction"],
    "Horror": ["Horror"],
    "Family Movie Night": ["Family"],
}

# ── TMDb Collection IDs for poster art ────────────────────────
TMDB_COLLECTION_IDS = {
    "Marvel": 529892,
    "Spider-Man": 531241,
    "Mission: Impossible": 87359,
    "Transformers": 8650,
    "X-Men": 748,
    "Jason Bourne": 31562,
    "Pirates of the Caribbean": 295,
    "Knives Out": 722971,
    "Kingsman": 391860,
    "Star Trek": 115575,
    "Toy Story": 10194,
    "Tron": 63043,
    "John Wick": 404609,
    "Harry Potter": 1241,
    "James Bond": 645,
    "Kung Fu Panda": 77816,
    "Cars": 87118,
    "Frozen": 386382,
    "Finding Nemo": 137697,
    "Monsters, Inc.": 137696,
    "The Incredibles": 468222,
    "Fifty Shades": 344830,
    "The Twilight Saga": 33514,
    "DC": 209131,
    "DreamWorks": None,
    "Lucasfilm": 10,
}

# ── TMDb search terms for poster art (non-collection) ────────
TMDB_SEARCH_TERMS = {
    "Pixar": "Pixar",
    "Disney": "Walt Disney",
    "Studio Ghibli": "Studio Ghibli",
    "A24": "A24",
    "Christopher Nolan": "Christopher Nolan",
    "Animation": "animation",
    "Sci-Fi": "science fiction",
    "Horror": "horror",
    "Family Movie Night": "family",
}


def jf_api(endpoint, method="GET", data=None, content_type="application/json"):
    sep = "&" if "?" in endpoint else "?"
    url = JF_URL + endpoint + sep + "api_key=" + JF_KEY
    req = urllib.request.Request(url, method=method)
    if data is not None:
        if isinstance(data, bytes):
            req.data = data
        else:
            req.data = json.dumps(data).encode()
        req.add_header("Content-Type", content_type)
    try:
        with urllib.request.urlopen(req) as resp:
            body = resp.read().decode()
            return json.loads(body) if body.strip() else {}
    except urllib.error.HTTPError as e:
        return None


def tmdb_api(endpoint):
    url = "https://api.themoviedb.org/3" + endpoint
    sep = "&" if "?" in endpoint else "?"
    url += sep + "api_key=" + TMDB_KEY
    req = urllib.request.Request(url)
    try:
        with urllib.request.urlopen(req) as resp:
            return json.loads(resp.read().decode())
    except:
        return None


def get_all_movies():
    data = jf_api("/Items?IncludeItemTypes=Movie&Recursive=true&Fields=Studios,Genres&Limit=10000")
    return data.get("Items", []) if data else []


def get_existing_collections():
    data = jf_api("/Items?IncludeItemTypes=BoxSet&Recursive=true&Limit=1000")
    if not data:
        return {}
    return {item["Name"]: item["Id"] for item in data.get("Items", [])}


def get_collection_items(collection_id):
    data = jf_api("/Items?ParentId=" + collection_id + "&Recursive=true&Limit=1000")
    if not data:
        return set()
    return {item["Id"] for item in data.get("Items", [])}


def create_collection(name):
    encoded = urllib.parse.quote(name)
    data = jf_api("/Collections?Name=" + encoded + "&IsLocked=true", method="POST")
    if data and "Id" in data:
        return data["Id"]
    return None


def add_to_collection(collection_id, item_ids):
    ids_str = ",".join(item_ids)
    jf_api("/Collections/" + collection_id + "/Items?Ids=" + ids_str, method="POST")


def set_collection_poster(collection_id, image_data):
    """Upload poster image to a Jellyfin collection (base64 encoded)."""
    import base64
    url = JF_URL + "/Items/" + collection_id + "/Images/Primary?api_key=" + JF_KEY
    req = urllib.request.Request(url, method="POST")
    req.data = base64.b64encode(image_data)
    req.add_header("Content-Type", "image/jpeg")
    try:
        with urllib.request.urlopen(req) as resp:
            return True
    except:
        return False


def has_poster(collection_id):
    """Check if collection already has a poster."""
    url = JF_URL + "/Items/" + collection_id + "/Images?api_key=" + JF_KEY
    req = urllib.request.Request(url)
    try:
        with urllib.request.urlopen(req) as resp:
            images = json.loads(resp.read().decode())
            return any(img.get("ImageType") == "Primary" for img in images)
    except:
        return False


def fetch_tmdb_poster(collection_name):
    """Try to get a poster from TMDb for the collection."""
    os.makedirs(POSTER_CACHE, exist_ok=True)
    cache_file = os.path.join(POSTER_CACHE, collection_name.replace("/", "_").replace(" ", "_") + ".jpg")

    # Use cached poster if exists
    if os.path.exists(cache_file) and os.path.getsize(cache_file) > 1000:
        with open(cache_file, "rb") as f:
            return f.read()

    poster_path = None

    # Try TMDb collection ID first
    if collection_name in TMDB_COLLECTION_IDS and TMDB_COLLECTION_IDS[collection_name]:
        coll_id = TMDB_COLLECTION_IDS[collection_name]
        data = tmdb_api("/collection/" + str(coll_id))
        if data and data.get("poster_path"):
            poster_path = data["poster_path"]

    # Fall back to searching TMDb collections
    if not poster_path:
        term = TMDB_SEARCH_TERMS.get(collection_name, collection_name)
        data = tmdb_api("/search/collection?query=" + urllib.parse.quote(term))
        if data and data.get("results"):
            for result in data["results"]:
                if result.get("poster_path"):
                    poster_path = result["poster_path"]
                    break

    if not poster_path:
        return None

    # Download poster
    img_url = TMDB_IMG + poster_path
    try:
        req = urllib.request.Request(img_url)
        with urllib.request.urlopen(req) as resp:
            img_data = resp.read()
            # Cache it
            with open(cache_file, "wb") as f:
                f.write(img_data)
            return img_data
    except:
        return None


def sync_collection(name, matched_ids, existing, movies_list=None):
    """Create or update a collection and return its ID."""
    if not matched_ids:
        return None

    if name in existing:
        coll_id = existing[name]
        current_items = get_collection_items(coll_id)
        new_items = matched_ids - current_items
        if new_items:
            add_to_collection(coll_id, new_items)
            print("[UPDATE] " + name + " -- added " + str(len(new_items)) + " (" + str(len(matched_ids)) + " total)")
        else:
            print("[OK] " + name + " -- " + str(len(matched_ids)) + " items, up to date")
        return coll_id
    else:
        coll_id = create_collection(name)
        if coll_id:
            add_to_collection(coll_id, matched_ids)
            print("[CREATE] " + name + " -- " + str(len(matched_ids)) + " items")
            return coll_id
        else:
            print("[ERROR] " + name + " -- failed to create")
            return None


def main():
    print("Smart Collections Sync")
    print("=" * 50)

    movies = get_all_movies()
    print("Library: " + str(len(movies)) + " movies")

    existing = get_existing_collections()
    print("Existing collections: " + str(len(existing)))
    print()

    all_collection_ids = {}

    # ── Studio Collections ──
    print("-- Studios --")
    for coll_name, studios in STUDIO_COLLECTIONS.items():
        matched = set()
        for movie in movies:
            movie_studios = {s["Name"] for s in movie.get("Studios", [])}
            if movie_studios & set(studios):
                matched.add(movie["Id"])
        cid = sync_collection(coll_name, matched, existing)
        if cid:
            all_collection_ids[coll_name] = cid

    # ── Franchise Collections ──
    print("\n-- Franchises --")
    for coll_name, keywords in FRANCHISE_COLLECTIONS.items():
        matched = set()
        for movie in movies:
            name = movie.get("Name", "")
            for kw in keywords:
                if kw.lower() in name.lower():
                    matched.add(movie["Id"])
                    break
        cid = sync_collection(coll_name, matched, existing)
        if cid:
            all_collection_ids[coll_name] = cid

    # ── Genre Collections ──
    print("\n-- Genres --")
    for coll_name, genres in GENRE_COLLECTIONS.items():
        matched = set()
        for movie in movies:
            movie_genres = set(movie.get("Genres", []))
            if movie_genres & set(genres):
                matched.add(movie["Id"])
        cid = sync_collection(coll_name, matched, existing)
        if cid:
            all_collection_ids[coll_name] = cid

    # ── Fetch & Set Posters ──
    print("\n-- Posters --")
    # Refresh existing collections list to include newly created ones
    existing = get_existing_collections()

    for coll_name, coll_id in all_collection_ids.items():
        if has_poster(coll_id):
            print("[OK] " + coll_name + " -- poster exists")
            continue

        poster_data = fetch_tmdb_poster(coll_name)
        if poster_data:
            success = set_collection_poster(coll_id, poster_data)
            if success:
                print("[POSTER] " + coll_name + " -- set from TMDb")
            else:
                print("[FAIL] " + coll_name + " -- upload failed")
        else:
            print("[MISS] " + coll_name + " -- no poster found on TMDb")

        time.sleep(0.3)

    print("\nDone.")


if __name__ == "__main__":
    main()
