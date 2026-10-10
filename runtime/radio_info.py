"""Prefer ICY song titles over station prefixes and persistent playlist aliases."""
def display_info(title, artist, formatted, alias, is_stream, live):
    title, artist = str(title or '').strip(), str(artist or '').strip()
    if not is_stream:
        return ((artist + ' – ' if artist else '') + title) if title else (formatted or 'No playback')
    station = alias or artist or formatted or 'Internet radio'
    if not live:
        return station
    normalize = lambda value: ' '.join(value.casefold().split())
    if not title or normalize(title) in {normalize(station), normalize(artist)}:
        return 'No track information'
    # Some stations prepend their identity to StreamTitle; remove only an exact prefix.
    for prefix in {station, artist}:
        if not prefix: continue
        for separator in (' - ', ' – ', ' — '):
            full = prefix + separator
            if title.casefold().startswith(full.casefold()):
                title = title[len(full):].strip()
                break
    return title or 'No track information'
