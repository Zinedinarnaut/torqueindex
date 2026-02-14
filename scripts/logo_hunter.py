#!/usr/bin/env python3

import json
import os
import re
import subprocess
import sys
import tempfile
import urllib.parse
import urllib.request


STORES = [
    {"id": "21overlays", "name": "21 Overlays", "base_url": "https://21overlays.com.au"},
    {"id": "dubhaus", "name": "Dubhaus", "base_url": "https://dubhaus.com.au"},
    {"id": "modeautoconcepts", "name": "Mode Auto Concepts", "base_url": "https://modeautoconcepts.com"},
    {"id": "xforce", "name": "XForce", "base_url": "https://xforce.com.au"},
    {"id": "justjap", "name": "JustJap", "base_url": "https://justjap.com"},
    {"id": "modsdirect", "name": "Mods Direct", "base_url": "https://www.modsdirect.com.au"},
    {"id": "prospeedracing", "name": "Prospeed Racing", "base_url": "https://www.prospeedracing.com.au"},
    {"id": "shiftymods", "name": "Shifty Mods", "base_url": "https://shiftymods.com.au"},
    {"id": "hi-torqueperformance", "name": "Hi-Torque Performance", "base_url": "https://hi-torqueperformance.myshopify.com"},
    {"id": "performancewarehouse", "name": "Performance Warehouse", "base_url": "https://performancewarehouse.com.au"},
    {"id": "streetelement", "name": "Street Element", "base_url": "https://streetelement.com.au"},
    {"id": "allautomotiveparts", "name": "All Automotive Parts", "base_url": "https://allautomotiveparts.com.au"},
    {"id": "eziautoparts", "name": "Ezi Auto Parts", "base_url": "https://eziautoparts.com.au"},
    {"id": "autocave", "name": "Auto Cave", "base_url": "https://autocave.com.au"},
    {"id": "jtmauto", "name": "JTM Auto", "base_url": "https://jtmauto.com.au"},
    {"id": "tjautoparts", "name": "TJ Auto Parts", "base_url": "https://tjautoparts.com.au"},
    {"id": "nationwideautoparts", "name": "Nationwide Auto Parts", "base_url": "https://www.nationwideautoparts.com.au"},
    {"id": "chicaneaustralia", "name": "Chicane Australia", "base_url": "https://www.chicaneaustralia.com.au"},
]


USER_AGENT = "Mozilla/5.0 (compatible; TorqueIndexLogoHunter/0.1; +https://localhost)"


def fetch_html(url: str) -> str:
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(req, timeout=25) as resp:
        data = resp.read()
        # best-effort decoding
        try:
            return data.decode("utf-8", errors="replace")
        except Exception:
            return data.decode("latin-1", errors="replace")


def abs_url(base_url: str, maybe_url: str) -> str:
    if not maybe_url:
        return ""

    maybe_url = maybe_url.strip()
    if maybe_url.startswith("//"):
        return "https:" + maybe_url
    if maybe_url.startswith("http://") or maybe_url.startswith("https://"):
        return maybe_url
    return urllib.parse.urljoin(base_url + "/", maybe_url)


def parse_candidates(html: str, base_url: str) -> list[dict]:
    candidates: list[dict] = []

    # img tags
    for m in re.finditer(r"<img\b[^>]*>", html, flags=re.IGNORECASE):
        tag = m.group(0)
        src = _attr(tag, "src") or _attr(tag, "data-src") or ""
        srcset = _attr(tag, "srcset") or ""
        alt = _attr(tag, "alt") or ""
        cls = _attr(tag, "class") or ""
        _id = _attr(tag, "id") or ""

        urls = []
        if src:
            urls.append(src)
        if srcset:
            # take first url in srcset
            first = srcset.split(",")[0].strip().split(" ")[0]
            if first:
                urls.append(first)

        for u in urls:
            u_abs = abs_url(base_url, u)
            if u_abs:
                candidates.append(
                    {
                        "url": u_abs,
                        "alt": alt,
                        "class": cls,
                        "id": _id,
                        "source": "img",
                    }
                )

    # link rel icons / preload
    for m in re.finditer(r"<link\b[^>]*>", html, flags=re.IGNORECASE):
        tag = m.group(0)
        rel = (_attr(tag, "rel") or "").lower()
        href = _attr(tag, "href") or ""
        as_attr = (_attr(tag, "as") or "").lower()
        if not href:
            continue
        if "icon" in rel or ("preload" in rel and as_attr == "image"):
            candidates.append(
                {
                    "url": abs_url(base_url, href),
                    "alt": rel,
                    "class": "",
                    "id": "",
                    "source": "link",
                }
            )

    # meta items that could point to logo-ish images
    for m in re.finditer(r"<meta\b[^>]*>", html, flags=re.IGNORECASE):
        tag = m.group(0)
        prop = (_attr(tag, "property") or "").lower()
        name = (_attr(tag, "name") or "").lower()
        content = _attr(tag, "content") or ""
        key = prop or name
        if not content:
            continue
        if key in ("og:image", "twitter:image"):
            candidates.append(
                {
                    "url": abs_url(base_url, content),
                    "alt": key,
                    "class": "",
                    "id": "",
                    "source": "meta",
                }
            )

    # de-dupe by url
    seen = set()
    uniq = []
    for c in candidates:
        u = c.get("url", "")
        if not u or u in seen:
            continue
        seen.add(u)
        uniq.append(c)

    return uniq


def _attr(tag: str, name: str) -> str:
    # naive attribute extraction
    m = re.search(r"\b" + re.escape(name) + r"\s*=\s*(['\"])(.*?)\1", tag, flags=re.IGNORECASE)
    if m:
        return m.group(2)
    # unquoted
    m = re.search(r"\b" + re.escape(name) + r"\s*=\s*([^\s>]+)", tag, flags=re.IGNORECASE)
    if m:
        return m.group(1)
    return ""


def score_candidate(c: dict, store: dict) -> int:
    url = (c.get("url") or "").lower()
    alt = (c.get("alt") or "").lower()
    cls = (c.get("class") or "").lower()
    _id = (c.get("id") or "").lower()

    score = 0
    if "cdn.shopify.com" in url:
        score += 3
    if "logo" in url:
        score += 8
    if "logo" in alt or "logo" in cls or "logo" in _id:
        score += 6

    store_name = (store.get("name") or "").lower()
    if store_name and store_name in alt:
        score += 4

    if url.endswith(".svg"):
        score += 6
    elif url.endswith(".png"):
        score += 4
    elif url.endswith(".webp"):
        score += 3
    elif url.endswith(".ico"):
        score += 1
    elif url.endswith(".jpg") or url.endswith(".jpeg"):
        score -= 6

    # prefer header-ish assets
    if "header" in cls or "header" in url:
        score += 2
    if "icon" in url and "logo" not in url:
        score -= 1

    # deprioritize content images
    if any(token in url for token in ["banner", "slideshow", "hero", "collection", "product"]):
        score -= 3

    # tiny favicons are acceptable fallback but not first choice
    if "favicon" in url:
        score -= 1

    return score


def download(url: str, out_path: str) -> tuple[str, int]:
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(req, timeout=25) as resp:
        content_type = (resp.headers.get("Content-Type") or "").split(";")[0].strip().lower()
        data = resp.read()
        with open(out_path, "wb") as f:
            f.write(data)
        return content_type, len(data)


def is_transparent_image(path: str) -> bool:
    # For raster formats, require at least one transparent pixel.
    # ImageMagick: %[opaque] -> True means fully opaque. We want False.
    try:
        out = subprocess.check_output(["identify", "-format", "%[opaque]", path], stderr=subprocess.DEVNULL)
        val = out.decode("utf-8", errors="replace").strip().lower()
        return val == "false"
    except Exception:
        return False


def pick_logo_for_store(store: dict) -> tuple[str, dict]:
    html = fetch_html(store["base_url"])
    candidates = parse_candidates(html, store["base_url"])

    scored = sorted(
        [(score_candidate(c, store), c) for c in candidates],
        key=lambda x: x[0],
        reverse=True,
    )

    tried = 0
    for score, c in scored[:80]:
        url = c["url"]
        if not url:
            continue

        tried += 1
        with tempfile.TemporaryDirectory() as td:
            filename = os.path.join(td, "asset")
            try:
                content_type, size = download(url, filename)
            except Exception:
                continue

            # basic sanity: skip huge assets
            if size > 2_000_000:
                continue

            # accept SVG as "transparent" (vector), best effort.
            if url.lower().endswith(".svg") or content_type == "image/svg+xml":
                return url, {"score": score, "content_type": content_type, "source": c.get("source"), "tried": tried}

            # require raster transparency
            if content_type in ("image/png", "image/webp", "image/gif", "image/x-icon") or url.lower().endswith(
                (".png", ".webp", ".gif", ".ico")
            ):
                if is_transparent_image(filename):
                    return url, {"score": score, "content_type": content_type, "source": c.get("source"), "tried": tried}

    return "", {"score": None, "content_type": None, "source": None, "tried": tried}


def main() -> int:
    out = []
    failures = []

    for store in STORES:
        try:
            logo_url, meta = pick_logo_for_store(store)
        except Exception as e:
            failures.append({"id": store["id"], "error": str(e)})
            continue

        if not logo_url:
            failures.append({"id": store["id"], "error": "no transparent logo found"})
            continue

        out.append({**store, "logo_url": logo_url, "_meta": meta})

    print(json.dumps({"stores": out, "failures": failures}, indent=2))
    return 0 if not failures else 2


if __name__ == "__main__":
    raise SystemExit(main())
