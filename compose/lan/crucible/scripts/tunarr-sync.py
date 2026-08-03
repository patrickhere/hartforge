#!/usr/bin/env python3
"""
tunarr-sync.py -- auto-sync Tunarr channels from Jellyfin library.

runs nightly via cron. queries jellyfin for movies matching each channel's
rules (genre, studio, name patterns), then rebuilds tunarr programming
via API. new movies are picked up automatically.

channels:
  2  MCU Chronological  -- Marvel Studios, timeline order (TMDB-keyed)
  3  Harry Potter        -- name match, release order
  4  Star Wars           -- name match, episode order
  5  Spy Channel         -- Bond(Craig)+Bourne+MI+Kingsman, series-grouped shuffle
  6  Movie Night         -- all movies, shuffled
  7  Animation Station   -- Animation genre, shuffled

channel 1 (adult animation) is TV shows -- handled separately if needed.
"""

import json, os, random, sys, time, logging
import urllib.request

# ── config ──────────────────────────────────────────────────────
TUNARR = "http://localhost:8000"
# NOT localhost: jellyfin's port is bound to the LAN interface only
# ("10.1.0.52:8096:8096" in the crucible compose, a deliberate hardening
# choice), so 127.0.0.1:8096 refuses the connection. that is what made every
# channel report "0 programs" and the unit fail nightly. tunarr itself is on
# 0.0.0.0:8000 so its localhost URL below is fine.
JELLYFIN = "http://10.1.0.52:8096"
# secrets come from /opt/yams/scripts/.env (mode 600, gitignored) so this file
# can live in git. systemd supplies them via EnvironmentFile.
JF_KEY = os.environ["JF_KEY"]
JF_SOURCE_ID = os.environ["JF_SOURCE_ID"]
MOVIES_LIBRARY = "f137a2dd21bbc1b99aa5c0f6bf02a805"

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S"
)
log = logging.getLogger("tunarr-sync")

# ── MCU timeline order by TMDB ID ──────────────────────────────
# position in the MCU viewing timeline. new MCU films not in this
# list get appended at the end sorted by release year.
MCU_TIMELINE = [
    1771,    # Captain America: The First Avenger
    1726,    # Iron Man
    10138,   # Iron Man 2
    10195,   # Thor
    24428,   # The Avengers
    68721,   # Iron Man 3
    76338,   # Thor: The Dark World
    100402,  # Captain America: The Winter Soldier
    118340,  # Guardians of the Galaxy
    283995,  # Guardians of the Galaxy Vol. 2
    99861,   # Avengers: Age of Ultron
    271110,  # Captain America: Civil War
    284052,  # Doctor Strange
    315635,  # Spider-Man: Homecoming
    284053,  # Thor: Ragnarok
    299536,  # Avengers: Infinity War
    299534,  # Avengers: Endgame
    429617,  # Spider-Man: Far From Home
    634649,  # Spider-Man: No Way Home
    453395,  # Doctor Strange in the Multiverse of Madness
    616037,  # Thor: Love and Thunder
    447365,  # Guardians of the Galaxy Vol. 3
    533535,  # Deadpool & Wolverine
    822119,  # Captain America: Brave New World
]

# star wars episode order by TMDB ID
SW_ORDER = [
    1893,    # Episode I - The Phantom Menace
    1894,    # Episode II - Attack of the Clones
    1895,    # Episode III - Revenge of the Sith
    11,      # A New Hope
    1891,    # The Empire Strikes Back
    1892,    # Return of the Jedi
    140607,  # The Force Awakens
    181808,  # The Last Jedi
    181812,  # The Rise of Skywalker
]

# harry potter order by TMDB ID
HP_ORDER = [
    671,     # Philosopher's Stone
    672,     # Chamber of Secrets
    673,     # Prisoner of Azkaban
    674,     # Goblet of Fire
    675,     # Order of the Phoenix
    767,     # Half-Blood Prince
    12444,   # Deathly Hallows: Part 1
    12445,   # Deathly Hallows: Part 2
]

# spy channel franchise definitions
# each entry: (name_pattern, studio_pattern, tmdb_ids_for_ordering)
# Daniel Craig Bond TMDB IDs in order
BOND_CRAIG = [36557, 10764, 37724, 206647, 370172]
BOURNE_ORDER = [2501, 2502, 2503, 49040, 324668]
MI_ORDER = [954, 955, 956, 56292, 177677, 353081, 575264, 945961]
KINGSMAN_ORDER = [207703, 343668, 476669]


# ── helpers ─────────────────────────────────────────────────────

def api(method, path, data=None, base=TUNARR):
    url = f"{base}{path}"
    body = json.dumps(data).encode() if data else None
    req = urllib.request.Request(url, data=body, method=method)
    req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            raw = resp.read()
            return json.loads(raw) if raw else None
    except urllib.error.HTTPError as e:
        err = e.read().decode()
        log.error(f"{method} {path}: {e.code} {err[:300]}")
        return None

def jf_movies(extra_params=""):
    """Fetch movies from Jellyfin with optional filter params."""
    url = (f"{JELLYFIN}/Items?ParentId={MOVIES_LIBRARY}&Recursive=true"
           f"&IncludeItemTypes=Movie&Fields=ProductionYear,Studios,Genres,ProviderIds"
           f"&SortBy=SortName&SortOrder=Ascending{extra_params}&api_key={JF_KEY}")
    with urllib.request.urlopen(url, timeout=30) as resp:
        return json.loads(resp.read())["Items"]

def batch_lookup(jf_ids):
    """Batch lookup Jellyfin IDs -> Tunarr program data."""
    if not jf_ids:
        return {}
    ext_ids = [f"jellyfin|{JF_SOURCE_ID}|{jid}" for jid in jf_ids]
    result = api("POST", "/api/programming/batch/lookup", {"externalIds": ext_ids})
    if not result:
        return {}
    lookup = {}
    for uuid, prog in result.items():
        jf_ext_id = prog.get("externalId", "")
        if jf_ext_id:
            lookup[jf_ext_id] = prog
    return lookup

def make_program(prog, jf_id):
    """Convert batch lookup result to ContentProgram for channel programming."""
    uuid = prog["uuid"]
    ext_ids = []
    for ident in prog.get("identifiers", []):
        if ident["type"] == "jellyfin":
            ext_ids.append({
                "type": "multi",
                "source": "jellyfin",
                "sourceId": ident.get("sourceId", "Hartfin"),
                "id": ident["id"]
            })
        else:
            ext_ids.append({
                "type": "single",
                "source": ident["type"],
                "id": ident["id"]
            })
    return {
        "type": "content",
        "persisted": True,
        "duration": prog["duration"],
        "id": uuid,
        "uniqueId": uuid,
        "subtype": "movie",
        "title": prog["title"],
        "externalSourceType": "jellyfin",
        "externalSourceName": "Hartfin",
        "externalSourceId": JF_SOURCE_ID,
        "externalKey": jf_id,
        "externalIds": ext_ids
    }

def set_programming(channel_id, name, jf_ids, shuffle=False):
    """Set channel programming from ordered list of Jellyfin IDs."""
    lookup = batch_lookup(jf_ids)

    programs = []
    missing = []
    for jf_id in jf_ids:
        prog = lookup.get(jf_id)
        if prog:
            programs.append(make_program(prog, jf_id))
        else:
            missing.append(jf_id)

    if missing:
        log.warning(f"{name}: {len(missing)} items not found in Tunarr (may need library resync)")

    if not programs:
        log.error(f"{name}: no programs found, skipping")
        return False

    indices = list(range(len(programs)))
    if shuffle:
        random.shuffle(indices)

    # tunarr 1.3.8 changed the manual-programming schema. it used to take a
    # "programs" array plus a lineup of {"type":"index","index":N} references
    # into it; that now fails validation with
    #   body/lineup/N/type Invalid input   (FST_ERR_VALIDATION)
    # the lineup items are self-contained and there is no "programs" key at all.
    # per /openapi.json a content item requires exactly type, duration and id -
    # all of which make_program() already produces.
    ordered = [programs[i] for i in indices]
    lineup = [
        {"type": "content", "duration": p["duration"], "id": p["id"]}
        for p in ordered
    ]

    payload = {
        "type": "manual",
        "lineup": lineup,
        "append": False
    }

    result = api("POST", f"/api/channels/{channel_id}/programming", payload)
    if result is not None:
        log.info(f"{name}: loaded {len(programs)} programs")
        return True
    return False

def get_tmdb(movie):
    """Get TMDB ID as int from a Jellyfin movie item."""
    tmdb = movie.get("ProviderIds", {}).get("Tmdb", "")
    return int(tmdb) if tmdb.isdigit() else 0

def sort_by_tmdb_order(movies, tmdb_order):
    """Sort movies by a predefined TMDB ID order. Unknown IDs go at the end by year."""
    order_map = {tid: i for i, tid in enumerate(tmdb_order)}
    max_pos = len(tmdb_order)

    def sort_key(m):
        tmdb = get_tmdb(m)
        pos = order_map.get(tmdb, max_pos + m.get("ProductionYear", 9999))
        return pos

    return sorted(movies, key=sort_key)


# ── channel builders ────────────────────────────────────────────

def build_mcu():
    """MCU Chronological: Marvel Studios movies in timeline order."""
    movies = jf_movies("&Studios=Marvel%20Studios")
    # exclude Spider-Man 3 (tmdb=559) -- not MCU despite Marvel Studios tag
    movies = [m for m in movies if get_tmdb(m) != 559]
    ordered = sort_by_tmdb_order(movies, MCU_TIMELINE)
    return [m["Id"] for m in ordered], False

def build_harry_potter():
    """Harry Potter: name match, release order."""
    movies = jf_movies("&SearchTerm=Harry%20Potter")
    # filter to only actual HP movies
    movies = [m for m in movies if "Harry Potter" in m["Name"]]
    ordered = sort_by_tmdb_order(movies, HP_ORDER)
    return [m["Id"] for m in ordered], False

def build_star_wars():
    """Star Wars: name match, episode order."""
    all_movies = jf_movies()
    movies = [m for m in all_movies if "Star Wars" in m["Name"]
              or m["Name"] in ("The Empire Strikes Back", "Return of the Jedi")]
    ordered = sort_by_tmdb_order(movies, SW_ORDER)
    return [m["Id"] for m in ordered], False

def build_spy_channel():
    """Spy Channel: Bond(Craig) + Bourne + MI + Kingsman, series-grouped shuffle."""
    all_movies = jf_movies()

    # build franchise lists
    franchises = []

    # Daniel Craig Bond (Casino Royale 2006 onward from EON)
    bond_craig = [m for m in all_movies if get_tmdb(m) in BOND_CRAIG]
    bond_craig = sort_by_tmdb_order(bond_craig, BOND_CRAIG)
    if bond_craig:
        franchises.append(bond_craig)

    # Bourne
    bourne = [m for m in all_movies if "Bourne" in m["Name"]]
    bourne = sort_by_tmdb_order(bourne, BOURNE_ORDER)
    if bourne:
        franchises.append(bourne)

    # Mission: Impossible
    mi = [m for m in all_movies if "Mission: Impossible" in m["Name"]
          or m["Name"] == "Mission: Impossible"]
    mi = sort_by_tmdb_order(mi, MI_ORDER)
    if mi:
        franchises.append(mi)

    # Kingsman
    kingsman = [m for m in all_movies if "Kingsman" in m["Name"]
                or m["Name"] == "The King's Man"]
    kingsman = sort_by_tmdb_order(kingsman, KINGSMAN_ORDER)
    if kingsman:
        franchises.append(kingsman)

    # shuffle which franchise plays first, keep internal order
    random.shuffle(franchises)
    ids = [m["Id"] for franchise in franchises for m in franchise]
    return ids, False

def build_movie_night():
    """Movie Night: all movies, shuffled."""
    movies = jf_movies()
    return [m["Id"] for m in movies], True

def build_animation_station():
    """Animation Station: Animation genre, shuffled."""
    movies = jf_movies("&Genres=Animation")
    return [m["Id"] for m in movies], True


# ── main ────────────────────────────────────────────────────────

def main():
    log.info("tunarr-sync starting")

    # get channel map
    channels = api("GET", "/api/channels")
    if not channels:
        log.error("failed to fetch channels")
        sys.exit(1)

    ch_map = {c["name"]: c["id"] for c in channels}

    # fuzzy match helper -- find channel by keyword in name
    def find_channel(keyword):
        for name, cid in ch_map.items():
            if keyword.lower() in name.lower():
                return cid, name
        return None, None

    # trigger Jellyfin library resync in Tunarr first
    sources = api("GET", "/api/media-sources")
    if sources:
        for src in sources:
            if src["type"] == "jellyfin":
                for lib in src.get("libraries", []):
                    if lib.get("enabled"):
                        log.info(f"syncing Tunarr library: {lib['name']}")
                        # send without body to avoid empty JSON error
                        try:
                            scan_url = f"{TUNARR}/api/media-sources/{src['id']}/scan?libraryIds={lib['id']}"
                            scan_req = urllib.request.Request(scan_url, method="POST")
                            urllib.request.urlopen(scan_req, timeout=30)
                        except Exception as e:
                            log.warning(f"library scan request: {e}")
        # give it a moment to process
        time.sleep(5)

    # channel builders keyed by search keyword
    channel_defs = [
        ("marvel", build_mcu),
        ("wizarding", build_harry_potter),
        ("galaxy", build_star_wars),
        ("tradecraft", build_spy_channel),
        ("feature", build_movie_night),
        ("toonbox", build_animation_station),
    ]

    results = {}
    for keyword, builder in channel_defs:
        cid, ch_name = find_channel(keyword)
        if not cid:
            log.warning(f"no channel matching '{keyword}' found, skipping")
            continue

        try:
            jf_ids, shuffle = builder()
            if jf_ids:
                ok = set_programming(cid, ch_name, jf_ids, shuffle=shuffle)
                results[ch_name] = len(jf_ids) if ok else 0
            else:
                log.warning(f"{ch_name}: no movies matched")
                results[ch_name] = 0
        except Exception as e:
            log.error(f"{ch_name}: {e}")
            results[ch_name] = 0

    # summary
    log.info("sync complete:")
    for name, count in results.items():
        log.info(f"  {name}: {count} programs")

    total = sum(results.values())
    if total == 0:
        log.error("no programs loaded across any channel")
        sys.exit(1)

if __name__ == "__main__":
    main()
