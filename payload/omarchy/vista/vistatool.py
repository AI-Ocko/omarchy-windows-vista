"""vistatool.py -- read Windows Vista files for omarchy-windows-vista. Parses
bytes only: it never loads, links or runs anything it reads. Run with
`python3 -I`.

   vistatool.py peres <pe> <outdir> <TYPE,...|*>   PE resources: BITMAP -> .bmp,
                                                   PNG/JPEG data -> .png/.jpg, rest .bin
   vistatool.py icons <pe> <outdir> <size,...>     GROUP_ICON -> <outdir>/<size>/<id>.ico
                                                   (one image: the deepest at that size;
                                                   256 is Vista's PNG entry)
   vistatool.py wave <pe> <out.wav> <id>           WAVE resource <id>
   vistatool.py strip <pe> <outdir> <id>:<w>:<rrggbb>  BITMAP strip -> <h>/<n>.png
   vistatool.py msstyles <msstyles> <outdir>       visual style: props.json, parts.txt,
                                                   image/<id>.png, stream/<id>.png,
                                                   parts/<class>/<part>.<state>.<prop>.png
   vistatool.py xcursor <cursors> <user32.dll> <outdir>
   vistatool.py halfblock <in.ppm> <out.txt> color|mono   (terminal art)
                                                   the Windows Aero scheme as an Xcursor
                                                   theme (aero_*.cur/.ani; text select and
                                                   precision select are user32's, as in
                                                   Vista's own scheme)
"""
import json, os, struct, sys, zlib

RT = {1: "CURSOR", 2: "BITMAP", 3: "ICON", 4: "MENU", 5: "DIALOG", 6: "STRING", 10: "RCDATA",
      12: "GROUP_CURSOR", 14: "GROUP_ICON", 16: "VERSION", 24: "MANIFEST"}


def resources(path, want):
    """Yield (type label, resource name, raw bytes), first language only."""
    d = open(path, "rb").read()
    pe = struct.unpack_from("<I", d, 0x3C)[0]
    if d[:2] != b"MZ" or d[pe:pe + 4] != b"PE\0\0":
        sys.exit("not a PE file: " + path)
    nsec, = struct.unpack_from("<H", d, pe + 6)
    optsz, = struct.unpack_from("<H", d, pe + 20)
    opt = pe + 24
    magic, = struct.unpack_from("<H", d, opt)
    rsrc_rva, = struct.unpack_from("<I", d, opt + (96 if magic == 0x10B else 112) + 16)
    secs = [struct.unpack_from("<IIII", d, opt + optsz + 40 * i + 8) for i in range(nsec)]

    def off(rva):
        for vsz, va, rsz, rp in secs:
            if va <= rva < va + max(vsz, rsz):
                return rva - va + rp
        raise ValueError("rva %x unmapped" % rva)

    base = off(rsrc_rva)

    def entries(p):
        named, ids = struct.unpack_from("<HH", d, p + 12)
        for i in range(named + ids):
            n, o = struct.unpack_from("<II", d, p + 16 + 8 * i)
            if n & 0x80000000:
                q = base + (n & 0x7FFFFFFF)
                n = d[q + 2:q + 2 + 2 * struct.unpack_from("<H", d, q)[0]].decode("utf-16le")
            yield n, base + (o & 0x7FFFFFFF)

    for tname, tp in entries(base):
        label = RT.get(tname, str(tname)) if isinstance(tname, int) else tname
        if "*" not in want and label not in want:
            continue
        for rname, rp in entries(tp):
            _lang, lp = next(entries(rp))  # first language only
            rva, size = struct.unpack_from("<II", d, lp)
            yield label, rname, d[off(rva):off(rva) + size]


def bmp_file(dib):
    """A BITMAP resource (a DIB) as a .bmp file."""
    hsz, = struct.unpack_from("<I", dib, 0)
    bpp, comp, = struct.unpack_from("<HI", dib, 14)
    ncol = (struct.unpack_from("<I", dib, 32)[0] if hsz >= 36 else 0) or (1 << bpp if bpp <= 8 else 0)
    bits = 14 + hsz + (12 if comp == 3 and hsz == 40 else 0) + 4 * ncol
    return b"BM" + struct.pack("<IHHI", 14 + len(dib), 0, 0, bits) + dib


def peres(path, out, want):
    for label, rname, blob in resources(path, want):
        os.makedirs(os.path.join(out, label), exist_ok=True)
        name = str(rname).replace("/", "_")
        if label == "BITMAP":
            blob, name = bmp_file(blob), name + ".bmp"
        elif blob[:8] == b"\x89PNG\r\n\x1a\n":
            name += ".png"
        elif blob[:3] == b"\xff\xd8\xff":
            name += ".jpg"
        else:
            name += ".bin"
        with open(os.path.join(out, label, name), "wb") as f:
            f.write(blob)


def icons(path, out, sizes):
    """Each GROUP_ICON as single-image .ico files <size>/<id>.ico: the entry of
    exactly that size with the most colours (256 = the PNG entry, stored with
    width/height 0 in the directory)."""
    res = {(label, name): blob for label, name, blob in resources(path, {"ICON", "GROUP_ICON"})}
    for (label, gid), grp in sorted(res.items(), key=lambda x: str(x[0][1])):
        if label != "GROUP_ICON":
            continue
        _r, _t, n = struct.unpack_from("<HHH", grp, 0)
        best = {}
        for i in range(n):
            w, h, cc, _res, planes, bpp, size, nid = struct.unpack_from("<BBBBHHIH", grp, 6 + 14 * i)
            s = w or 256
            if s in sizes and (s not in best or bpp > best[s][0]) and ("ICON", nid) in res:
                best[s] = (bpp, w, h, cc, planes, nid)
        for s, (bpp, w, h, cc, planes, nid) in best.items():
            img = res[("ICON", nid)]
            os.makedirs(os.path.join(out, str(s)), exist_ok=True)
            with open(os.path.join(out, str(s), "%s.ico" % gid), "wb") as f:
                f.write(struct.pack("<HHH", 0, 1, 1) + struct.pack("<BBBBHHII", w, h, cc, 0, planes, bpp, len(img), 22) + img)


def wave(path, dst, rid):
    for label, name, blob in resources(path, {"WAVE"}):
        if str(name) == rid:
            open(dst, "wb").write(blob)
            return
    sys.exit("no WAVE resource %s in %s" % (rid, path))


# ---------------------------------------------------------------- pixels

def dib_rows(dib):
    """BITMAP resource DIB (BI_RGB 1/4/8/24/32 bpp, BI_RLE8, BI_RLE4) -> w, h, top-down rows of (r, g, b)."""
    hsz, w, h, _pl, bpp, comp = struct.unpack_from("<IiiHHI", dib, 0)
    ncol = (struct.unpack_from("<I", dib, 32)[0] if hsz >= 36 else 0) or (1 << bpp if bpp <= 8 else 0)
    pal = [tuple(dib[hsz + 4 * i:hsz + 4 * i + 3][::-1]) for i in range(ncol)]
    bits, topdown, h = hsz + 4 * ncol, h < 0, abs(h)
    if comp in (1, 2):  # RLE8 / RLE4: (count, value) runs and escapes, bottom-up
        idx, x, y, p = [[0] * w for _ in range(h)], 0, 0, bits
        nib = lambda b, k: b if comp == 1 else (b >> 4 if k % 2 == 0 else b & 15)
        def put(v):
            if x < w and y < h:
                idx[y][x] = v
        while p + 1 < len(dib):
            n, c = dib[p], dib[p + 1]
            p += 2
            if n:
                for k in range(n):
                    put(nib(c, k)); x += 1
            elif c == 0:
                x, y = 0, y + 1
            elif c == 1:
                break
            elif c == 2:
                x, y, p = x + dib[p], y + dib[p + 1], p + 2
            else:
                for k in range(c):
                    put(dib[p + k] if comp == 1 else nib(dib[p + k // 2], k)); x += 1
                nbytes = c if comp == 1 else (c + 1) // 2
                p += nbytes + (nbytes & 1)
        rows = [[pal[v] for v in r] for r in idx]
    elif comp == 0:
        stride, rows = ((w * bpp + 31) // 32) * 4, []
        for y in range(h):
            r, row = dib[bits + y * stride:bits + (y + 1) * stride], []
            for x in range(w):
                if bpp <= 8:
                    b = x * bpp
                    row.append(pal[(r[b // 8] >> (8 - bpp - b % 8)) & ((1 << bpp) - 1)])
                else:
                    o = x * bpp // 8
                    row.append((r[o + 2], r[o + 1], r[o]))
            rows.append(row)
    else:
        sys.exit("unsupported BMP compression %d" % comp)
    if not topdown:
        rows.reverse()
    return w, h, rows


def png(path, w, h, rows):
    """RGBA rows -> PNG. Stored (uncompressed) deflate blocks, so the bytes
    never depend on the zlib build and the output can be pinned by sha256."""
    raw = b"".join(b"\0" + bytes(c for px in row for c in px) for row in rows)
    z = b"\x78\x01"
    for i in range(0, len(raw), 65535):
        blk = raw[i:i + 65535]
        z += bytes([i + 65535 >= len(raw)]) + struct.pack("<HH", len(blk), len(blk) ^ 0xFFFF) + blk
    z += struct.pack(">I", zlib.adler32(raw))
    chunk = lambda t, d: struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d))
    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
                + chunk(b"IDAT", z) + chunk(b"IEND", b""))


def png_rgba(data):
    """Decode an 8-bit RGBA / RGB / grey(+alpha) / palette PNG -> w, h, rows of (r, g, b, a)."""
    p, idat, pal, trns = 8, b"", None, None
    while p < len(data):
        n, = struct.unpack_from(">I", data, p)
        t, d = data[p + 4:p + 8], data[p + 8:p + 8 + n]
        if t == b"IHDR":
            w, h, depth, ctype, _c, _f, inter = struct.unpack(">IIBBBBB", d)
        elif t == b"PLTE":
            pal = [tuple(d[i:i + 3]) for i in range(0, len(d), 3)]
        elif t == b"tRNS":
            trns = d
        elif t == b"IDAT":
            idat += d
        p += 12 + n
    if depth != 8 or inter:
        sys.exit("unsupported PNG (depth %d, interlace %d)" % (depth, inter))
    bpp = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}[ctype]
    raw, stride, prev, rows, o = zlib.decompress(idat), w * bpp, bytearray(w * bpp), [], 0
    for _y in range(h):
        f, line = raw[o], bytearray(raw[o + 1:o + 1 + stride])
        o += 1 + stride
        for i in range(stride):
            a = line[i - bpp] if i >= bpp else 0
            b, c = prev[i], prev[i - bpp] if i >= bpp else 0
            if f == 1: line[i] = (line[i] + a) & 255
            elif f == 2: line[i] = (line[i] + b) & 255
            elif f == 3: line[i] = (line[i] + (a + b) // 2) & 255
            elif f == 4:
                pa, pb, pc = abs(b - c), abs(a - c), abs(a + b - 2 * c)
                line[i] = (line[i] + (a if pa <= pb and pa <= pc else b if pb <= pc else c)) & 255
        prev = line
        row = []
        for x in range(w):
            q = line[x * bpp:(x + 1) * bpp]
            if ctype == 6: row.append(tuple(q))
            elif ctype == 2: row.append((*q, 255))
            elif ctype == 0: row.append((q[0], q[0], q[0], 255))
            elif ctype == 4: row.append((q[0], q[0], q[0], q[1]))
            else: row.append((*pal[q[0]], trns[q[0]] if trns and q[0] < len(trns) else 255))
        rows.append(row)
    return w, h, rows


def strip(path, out, spec):
    """A BITMAP that is a horizontal strip of equal frames on a colour key."""
    rid, fw, key = spec.split(":")
    fw, key = int(fw), tuple(bytes.fromhex(key))
    dib = next(blob for label, name, blob in resources(path, {"BITMAP"}) if str(name) == rid)
    w, h, rows = dib_rows(dib)
    os.makedirs(os.path.join(out, str(h)))
    for n in range(w // fw):
        frame = [[(*px, 255) if px != key else (0, 0, 0, 0) for px in row[n * fw:(n + 1) * fw]] for row in rows]
        png(os.path.join(out, str(h), "%d.png" % n), fw, h, frame)


# ---------------------------------------------------------------- msstyles
#
# A Vista .msstyles keeps its images as PNG streams in IMAGE resources and its
# properties in the binary VARIANT resource "NORMAL" (the one variant Vista's
# Aero ships), not XP's INI text. Layout, worked out on Vista SP2's
# aero.msstyles and checked to parse it end to end (4364 records, ending on
# the resource's last byte):
#   CMAP      class names, UTF-16, NUL-terminated, each padded to 8 bytes;
#             a property's classID indexes the non-empty names
#   VARIANT   records: header <nameID typeID classID partID stateID shortRef
#             reserved size> (8 x int32), then `size` bytes of value padded to
#             8 -- unless shortRef != 0, when the value is a reference held in
#             the header itself and no bytes follow: an IMAGE resource id for
#             FILENAME properties, a string id (MUI) for FONT ones
# nameID/typeID are the TMT_* property ids of vssym32.h.
# DWMWindow (the Aero glass frame and caption buttons DWM draws) has no image
# files: its part 0 holds a DISKSTREAM, the id of a STREAM resource that is
# one PNG atlas, and each part an ATLASRECT <left top right bottom> in it.

TYPES = {200: "enum", 201: "string", 202: "int", 203: "bool", 204: "color", 205: "margins",
         206: "filename", 207: "size", 208: "position", 209: "rect", 210: "font", 211: "intlist",
         212: "hbitmap", 213: "diskstream", 214: "stream", 215: "bitmapref", 216: "float", 217: "floatlist"}
# vssym32.h names for the properties the dumps are read for; others print as numbers.
PROPS = {2201: "TRANSPARENT", 2202: "AUTOSIZE", 2203: "BORDERONLY", 2204: "COMPOSITED", 2205: "BGFILL",
         2209: "MIRRORIMAGE", 2210: "UNIFORMSIZING", 2211: "INTEGRALSIZING", 2217: "TEXTGLOW",
         2401: "IMAGECOUNT", 2402: "ALPHALEVEL", 2403: "BORDERSIZE", 2404: "ROUNDCORNERWIDTH",
         2405: "ROUNDCORNERHEIGHT", 2411: "PROGRESSCHUNKSIZE", 2412: "PROGRESSSPACESIZE",
         2414: "TEXTBORDERSIZE", 2415: "ALPHATHRESHOLD", 2416: "WIDTH", 2417: "HEIGHT",
         2425: "TEXTGLOWSIZE", 2429: "GLOWINTENSITY", 2430: "OPACITY", 2431: "COLORIZATIONCOLOR",
         2432: "COLORIZATIONOPACITY",
         3001: "IMAGEFILE", 3002: "IMAGEFILE1", 3003: "IMAGEFILE2", 3004: "IMAGEFILE3",
         3005: "IMAGEFILE4", 3006: "IMAGEFILE5", 3008: "GLYPHIMAGEFILE",
         3401: "OFFSET", 3402: "TEXTSHADOWOFFSET", 3403: "MINSIZE", 3404: "MINSIZE1",
         3405: "MINSIZE2", 3406: "MINSIZE3", 3407: "MINSIZE4", 3408: "MINSIZE5", 3409: "NORMALSIZE",
         3601: "SIZINGMARGINS", 3602: "CONTENTMARGINS", 3603: "CAPTIONMARGINS",
         3801: "BORDERCOLOR", 3802: "FILLCOLOR", 3803: "TEXTCOLOR", 3809: "TRANSPARENTCOLOR",
         3810: "GRADIENTCOLOR1", 3811: "GRADIENTCOLOR2", 3812: "GRADIENTCOLOR3",
         3813: "GRADIENTCOLOR4", 3814: "GRADIENTCOLOR5", 3815: "SHADOWCOLOR", 3816: "GLOWCOLOR",
         3817: "TEXTBORDERCOLOR", 3818: "TEXTSHADOWCOLOR", 3819: "GLYPHTEXTCOLOR",
         3821: "FILLCOLORHINT", 3822: "BORDERCOLORHINT", 3823: "ACCENTCOLORHINT",
         3824: "TEXTCOLORHINT",
         4001: "BGTYPE", 4002: "BORDERTYPE", 4003: "FILLTYPE", 4004: "SIZINGTYPE", 4005: "HALIGN",
         4006: "CONTENTALIGNMENT", 4007: "VALIGN", 4008: "OFFSETTYPE", 4010: "TEXTSHADOWTYPE",
         4011: "IMAGELAYOUT", 4012: "GLYPHTYPE", 4013: "IMAGESELECTTYPE",
         4015: "TRUESIZESCALINGTYPE", 213: "DISKSTREAM", 8002: "ATLASRECT"}
# vsstyle.h part names for the classes Vista's look is built from. Classes
# with a "Prefix::" share their base class's parts; DWMWindow's parts are not
# in the public headers and print as numbers.
PARTS = {
    "Window": "CAPTION SMALLCAPTION MINCAPTION SMALLMINCAPTION MAXCAPTION SMALLMAXCAPTION FRAMELEFT "
              "FRAMERIGHT FRAMEBOTTOM SMALLFRAMELEFT SMALLFRAMERIGHT SMALLFRAMEBOTTOM SYSBUTTON "
              "MDISYSBUTTON MINBUTTON MDIMINBUTTON MAXBUTTON CLOSEBUTTON SMALLCLOSEBUTTON MDICLOSEBUTTON "
              "RESTOREBUTTON MDIRESTOREBUTTON HELPBUTTON MDIHELPBUTTON HORZSCROLL HORZTHUMB VERTSCROLL "
              "VERTTHUMB DIALOG CAPTIONSIZINGTEMPLATE SMALLCAPTIONSIZINGTEMPLATE FRAMELEFTSIZINGTEMPLATE "
              "SMALLFRAMELEFTSIZINGTEMPLATE FRAMERIGHTSIZINGTEMPLATE SMALLFRAMERIGHTSIZINGTEMPLATE "
              "FRAMEBOTTOMSIZINGTEMPLATE SMALLFRAMEBOTTOMSIZINGTEMPLATE FRAME",
    "Button": "PUSHBUTTON RADIOBUTTON CHECKBOX GROUPBOX USERBUTTON COMMANDLINK COMMANDLINKGLYPH",
    "Tooltip": "STANDARD STANDARDTITLE BALLOON BALLOONTITLE CLOSE BALLOONSTEM WRENCH",
    "Progress": "BAR BARVERT CHUNK CHUNKVERT FILL FILLVERT PULSEOVERLAY MOVEOVERLAY PULSEOVERLAYVERT "
                "MOVEOVERLAYVERT TRANSPARENTBAR TRANSPARENTBARVERT",
    "Tab": "TABITEM TABITEMLEFTEDGE TABITEMRIGHTEDGE TABITEMBOTHEDGE TOPTABITEM TOPTABITEMLEFTEDGE "
           "TOPTABITEMRIGHTEDGE TOPTABITEMBOTHEDGE PANE BODY AEROWIZARDBODY",
    "ScrollBar": "ARROWBTN THUMBBTNHORZ THUMBBTNVERT LOWERTRACKHORZ UPPERTRACKHORZ LOWERTRACKVERT "
                 "UPPERTRACKVERT GRIPPERHORZ GRIPPERVERT SIZEBOX",
    "TaskBar": "BACKGROUNDBOTTOM BACKGROUNDRIGHT BACKGROUNDTOP BACKGROUNDLEFT SIZINGBARBOTTOM "
               "SIZINGBARRIGHT SIZINGBARTOP SIZINGBARLEFT",
    "TaskBand": "GROUPCOUNT FLASHBUTTON FLASHBUTTONGROUPMENU",
    "StartPanel": "USERPANE MOREPROGRAMS MOREPROGRAMSARROW PROGLIST PROGLISTSEPARATOR PLACESLIST "
                  "PLACESLISTSEPARATOR LOGOFF LOGOFFBUTTONS USERPICTURE PREVIEW MOREPROGRAMSTAB "
                  "NSCHOST SOFTWAREEXPLORER OPENBOX SEARCHVIEW MOREPROGRAMSARROWBACK TOPMATCH "
                  "LOGOFFSPLITBUTTONDROPDOWN",
    "ListView": "LISTITEM LISTGROUP LISTDETAIL LISTSORTEDDETAIL EMPTYTEXT GROUPHEADER GROUPHEADERLINE "
                "EXPANDBUTTON COLLAPSEBUTTON COLUMNDETAIL",
    "Toolbar": "BUTTON DROPDOWNBUTTON SPLITBUTTON SPLITBUTTONDROPDOWN SEPARATOR SEPARATORVERT",
    "TrayNotify": "BACKGROUND ANIMBACKGROUND",
    "Rebar": "GRIPPER GRIPPERVERT BAND CHEVRON CHEVRONVERT BACKGROUND SPLITTER SPLITTERVERT",
}
PARTS = {k: v.split() for k, v in PARTS.items()}


def msstyles_records(path):
    res = {}
    for label, name, blob in resources(path, {"CMAP", "VARIANT", "IMAGE", "STREAM"}):
        res[(label, str(name))] = blob
    classes = [c for c in res[("CMAP", "CMAP")].decode("utf-16le").split("\0") if c]
    v, p, recs = res[("VARIANT", "NORMAL")], 0, []
    while p < len(v):
        name, typ, cls, part, state, ref, _r, size = struct.unpack_from("<8i", v, p)
        if typ not in TYPES:
            sys.exit("msstyles: unknown property type %d at %d (format changed?)" % (typ, p))
        data = b"" if ref else v[p + 32:p + 32 + size]
        recs.append((classes[cls], part, state, name, typ, ref, data))
        p += 32 if ref else 32 + (size + 7) // 8 * 8
    if p != len(v):
        sys.exit("msstyles: VARIANT did not end on a record boundary")
    return classes, recs, res


def decode(typ, ref, data):
    t = TYPES[typ]
    if ref:
        return ref
    if t in ("enum", "int", "size", "bool"):
        n, = struct.unpack_from("<i", data)
        return bool(n) if t == "bool" else n
    if t == "color":
        c, = struct.unpack_from("<I", data)
        return "#%02X%02X%02X" % (c & 255, c >> 8 & 255, c >> 16 & 255)
    if t in ("margins", "rect", "position"):
        return list(struct.unpack_from("<%di" % (len(data) // 4), data))
    if t == "intlist":
        n, = struct.unpack_from("<i", data)
        return list(struct.unpack_from("<%di" % n, data, 4))
    if t == "string":
        return data.decode("utf-16le").split("\0")[0]
    if t == "float":
        return struct.unpack_from("<f", data)[0]
    return data.hex()


def part_name(cls, part):
    base = cls.split("::")[-1]
    names = PARTS.get(base) or PARTS.get(base.title()) or []
    return names[part - 1] if 0 < part <= len(names) else str(part)


def msstyles(path, out):
    classes, recs, res = msstyles_records(path)
    os.makedirs(os.path.join(out, "image"))
    os.makedirs(os.path.join(out, "stream"))
    for (label, name), blob in sorted(res.items()):
        if label in ("IMAGE", "STREAM"):
            open(os.path.join(out, label.lower(), name + ".png"), "wb").write(blob)
    props, lines = {}, []
    for cls, part, state, name, typ, ref, data in recs:
        key = "%s/%s.%d" % (cls, part_name(cls, part), state)
        props.setdefault(key, {})[PROPS.get(name, str(name))] = decode(typ, ref, data)
    for key in sorted(props, key=str.lower):
        pr = props[key]
        cls, rest = key.rsplit("/", 1)
        imgs = {k: v for k, v in pr.items() if k.startswith("IMAGEFILE") or k == "GLYPHIMAGEFILE"}
        for k, iid in sorted(imgs.items()):
            blob = res.get(("IMAGE", str(iid)))
            if blob is None:
                continue
            w, h = struct.unpack_from(">II", blob, 16)
            d = os.path.join(out, "parts", cls.replace("::", "__"))
            os.makedirs(d, exist_ok=True)
            open(os.path.join(d, "%s.%s.png" % (rest, k)), "wb").write(blob)
            lines.append("%-48s %-14s image %4d %4dx%-4d count %-3s layout %-4s sizing %-5s margins %s content %s" % (
                key, k, iid, w, h, pr.get("IMAGECOUNT", 1), {0: "vert", 1: "horz"}.get(pr.get("IMAGELAYOUT"), "-"),
                {0: "true", 1: "stretch", 2: "tile"}.get(pr.get("SIZINGTYPE"), "-"),
                pr.get("SIZINGMARGINS", "-"), pr.get("CONTENTMARGINS", "-")))
    # Atlas parts: cut each ATLASRECT out of its class's DISKSTREAM PNG.
    atlases = {}
    for key, pr in props.items():
        if "DISKSTREAM" in pr and ("STREAM", str(pr["DISKSTREAM"])) in res:
            atlases[key.rsplit("/", 1)[0]] = png_rgba(res[("STREAM", str(pr["DISKSTREAM"]))])
    for key in sorted(props, key=str.lower):
        pr = props[key]
        cls, rest = key.rsplit("/", 1)
        if "ATLASRECT" not in pr or cls not in atlases:
            continue
        l, t, r, b = pr["ATLASRECT"]
        _w, _h, rows = atlases[cls]
        d = os.path.join(out, "parts", cls.replace("::", "__"))
        os.makedirs(d, exist_ok=True)
        png(os.path.join(d, "%s.ATLAS.png" % rest), r - l, b - t, [row[l:r] for row in rows[t:b]])
        lines.append("%-48s %-14s atlas %4s %4dx%-4d count %-3s layout %-4s sizing %-5s margins %s content %s" % (
            key, "ATLASRECT", "", r - l, b - t, pr.get("IMAGECOUNT", 1), "vert", "-",
            pr.get("SIZINGMARGINS", "-"), pr.get("CONTENTMARGINS", "-")))
    with open(os.path.join(out, "props.json"), "w") as f:
        json.dump({"classes": classes, "records": len(recs), "props": props}, f, indent=1, sort_keys=True)
        f.write("\n")
    with open(os.path.join(out, "parts.txt"), "w") as f:
        f.write("# class/part.state  property  IMAGE id  size  frames  layout  sizing  SIZINGMARGINS (l r t b)  CONTENTMARGINS\n")
        f.write("\n".join(lines) + "\n")


# ---------------------------------------------------------------- cursors
#
# Vista's "Windows Aero" pointer scheme: aero_*.cur / .ani at three sizes
# (normal 32 px, _l 48 px, _xl 64 px). Text select and precision select are
# blank in that scheme, i.e. user32.dll's own I-beam and crosshair (GROUP_CURSOR
# 101 and 103, the same ids as XP's user32).
# Xcursor nominal sizes follow XP's: 24 = the 32 px art (Windows at 96 dpi),
# 36 = _l, 48 = _xl.
XCURSORS = {
    "aero_arrow": "default left_ptr arrow top_left_arrow left-arrow",
    "aero_helpsel": "help question_arrow whats_this left_ptr_help dnd-ask",
    "aero_working": "progress left_ptr_watch half-busy",
    "aero_busy": "wait watch",
    "aero_pen": "pencil",
    "aero_unavail": "not-allowed no-drop forbidden crossed_circle circle dnd-no-drop",
    "aero_ns": "ns-resize n-resize s-resize row-resize size_ver sb_v_double_arrow v_double_arrow top_side bottom_side split_v",
    "aero_ew": "ew-resize e-resize w-resize col-resize size_hor sb_h_double_arrow h_double_arrow left_side right_side split_h",
    "aero_nwse": "nwse-resize nw-resize se-resize size_fdiag bd_double_arrow top_left_corner bottom_right_corner",
    "aero_nesw": "nesw-resize ne-resize sw-resize size_bdiag fd_double_arrow top_right_corner bottom_left_corner",
    "aero_move": "move fleur size_all all-scroll",
    "aero_up": "up-arrow center_ptr sb_up_arrow",
    "aero_link": "pointer hand hand1 hand2 pointing_hand",
    "user32:101": "text xterm ibeam",
    "user32:103": "crosshair cross tcross",
}
SIZES = (("", 24), ("_l", 36), ("_xl", 48))


def cur_image(blob):
    """One cursor image (a .cur directory entry's data, or a user32 CURSOR
    resource without its hotspot) -> w, h, rows of (r, g, b, a)."""
    if blob[:8] == b"\x89PNG\r\n\x1a\n":
        return png_rgba(blob)
    hsz, w, h2, _pl, bpp = struct.unpack_from("<IiiHH", blob, 0)
    h = h2 // 2
    ncol = (struct.unpack_from("<I", blob, 32)[0] if hsz >= 36 else 0) or (1 << bpp if bpp <= 8 else 0)
    pal = [tuple(blob[hsz + 4 * i:hsz + 4 * i + 3][::-1]) for i in range(ncol)]
    xstride, astride = ((w * bpp + 31) // 32) * 4, ((w + 31) // 32) * 4
    xor = hsz + 4 * ncol
    andm = xor + xstride * h
    rows = []
    has_alpha = bpp == 32 and any(blob[xor + i * 4 + 3] for i in range(w * h))
    for y in range(h):
        sy, row = h - 1 - y, []
        for x in range(w):
            masked = (blob[andm + sy * astride + x // 8] >> (7 - x % 8)) & 1
            if bpp == 32:
                o = xor + sy * xstride + 4 * x
                b, g, r, a = blob[o:o + 4]
                row.append((r, g, b, a if has_alpha else (0 if masked else 255)))
            else:
                bit = sy * xstride * 8 + x * bpp
                idx = (blob[xor + bit // 8] >> (8 - bpp - bit % 8)) & ((1 << bpp) - 1)
                rgb = pal[idx] if idx < len(pal) else (0, 0, 0)
                if not masked:
                    row.append((*rgb, 255))
                elif rgb == (0, 0, 0):
                    row.append((0, 0, 0, 0))
                else:  # screen-inverting pixel: Xcursor has no XOR mode; drawn black
                    row.append((0, 0, 0, 255))
        rows.append(row)
    return w, h, rows


def argb(rows):
    return b"".join(struct.pack("<I", a << 24 | (r * a // 255) << 16 | (g * a // 255) << 8 | b * a // 255)
                    for row in rows for (r, g, b, a) in row)


def cur_file(d):
    """.cur file bytes -> (hotspot x, y, w, h, rows) of its largest image."""
    _r, _t, n = struct.unpack_from("<HHH", d, 0)
    best = None
    for i in range(n):
        w, h, _c, _x, hx, hy, size, off = struct.unpack_from("<BBBBHHII", d, 6 + 16 * i)
        if best is None or (w or 256) > best[0]:
            best = (w or 256, hx, hy, d[off:off + size])
    _s, hx, hy, blob = best
    w, h, rows = cur_image(blob)
    return hx, hy, w, h, rows


def ani_file(d):
    """.ani (RIFF ACON) -> [(hotspot x, y, w, h, rows, delay ms)] in play order."""
    if d[:4] != b"RIFF" or d[8:12] != b"ACON":
        sys.exit("not an .ani file")
    p, frames, rate, seq, jif = 12, [], None, None, 6
    while p + 8 <= len(d):
        cid, n = d[p:p + 4], struct.unpack_from("<I", d, p + 4)[0]
        body = d[p + 8:p + 8 + n]
        if cid == b"anih":
            jif = struct.unpack_from("<I", body, 28)[0] or 6
        elif cid == b"rate":
            rate = list(struct.unpack_from("<%dI" % (n // 4), body))
        elif cid == b"seq ":
            seq = list(struct.unpack_from("<%dI" % (n // 4), body))
        elif cid == b"LIST" and body[:4] == b"fram":
            q = 4
            while q + 8 <= len(body):
                fid, fn = body[q:q + 4], struct.unpack_from("<I", body, q + 4)[0]
                if fid == b"icon":
                    frames.append(cur_file(body[q + 8:q + 8 + fn]))
                q += 8 + fn + (fn & 1)
        p += 8 + n + (n & 1)
    order = seq or list(range(len(frames)))
    return [(*frames[f], round((rate[i] if rate else jif) * 1000 / 60)) for i, f in enumerate(order)]


def xcursor(cdir, user32, out):
    cursors = {}
    for label, name, blob in resources(user32, {"CURSOR", "GROUP_CURSOR"}):
        cursors[(label, name)] = blob
    os.makedirs(os.path.join(out, "cursors"))
    for src, names in XCURSORS.items():
        images = []  # (nominal, hx, hy, w, h, rows, delay)
        if src.startswith("user32:"):
            grp = cursors[("GROUP_CURSOR", int(src.split(":")[1]))]
            nid, = struct.unpack_from("<H", grp, 6 + 12)
            c = cursors[("CURSOR", nid)]
            hx, hy = struct.unpack_from("<HH", c, 0)
            w, h, rows = cur_image(c[4:])
            for s in (1, 2):  # 24 = Windows' own pixels; 48 = doubled, nearest neighbour
                big = [[px for px in row for _ in range(s)] for row in rows for _ in range(s)]
                images.append((24 * s, hx * s, hy * s, w * s, h * s, big, 0))
        else:
            for suffix, nominal in SIZES:
                for ext in (".cur", ".ani"):
                    f = os.path.join(cdir, src + suffix + ext)
                    if not os.path.exists(f):
                        continue
                    d = open(f, "rb").read()
                    if ext == ".cur":
                        images.append((nominal, *cur_file(d), 0))
                    else:
                        images += [(nominal, *fr) for fr in ani_file(d)]
        if not images:
            sys.exit("no images for " + src)
        chunks = [struct.pack("<9I", 36, 0xFFFD0002, nom, 1, w, h, hx, hy, delay) + argb(rows)
                  for nom, hx, hy, w, h, rows, delay in images]
        toc, pos = b"", 16 + 12 * len(chunks)
        for (nom, *_rest), ch in zip(images, chunks):
            toc += struct.pack("<3I", 0xFFFD0002, nom, pos)
            pos += len(ch)
        names = names.split()
        with open(os.path.join(out, "cursors", names[0]), "wb") as f:
            f.write(b"Xcur" + struct.pack("<3I", 16, 0x10000, len(chunks)) + toc + b"".join(chunks))
        for n in names[1:]:
            os.symlink(names[0], os.path.join(out, "cursors", n))
    with open(os.path.join(out, "index.theme"), "w") as f:
        f.write("[Icon Theme]\nName=Windows Vista Aero\n"
                "Comment=Windows Vista's Aero pointers, converted from aero_*.cur/.ani\nInherits=Adwaita\n")



def halfblock(src, dst, mode):
    """Binary PPM (P6, maxval 255) -> text, two pixel rows per line. color:
    U+2580 with 24-bit fg = top pixel, bg = bottom pixel, black left to the
    terminal (the logo is rendered on black). mono: pixels brighter than 96
    become U+2580/U+2584/U+2588, for the stock screensaver's plain text."""
    d = open(src, "rb").read()
    head = d.split(maxsplit=4)
    assert head[0] == b"P6" and head[3] == b"255", "need a binary P6 PPM"
    w, h = int(head[1]), int(head[2])
    px = d[len(d) - 3 * w * h:]
    get = lambda x, y: tuple(px[3 * (y * w + x):3 * (y * w + x) + 3]) if y < h else (0, 0, 0)
    lines = []
    for y in range(0, h, 2):
        out = ""
        for x in range(w):
            t, b = get(x, y), get(x, y + 1)
            if mode == "mono":
                on = (sum(t) > 288, sum(b) > 288)
                out += {(0, 0): " ", (1, 0): "▀", (0, 1): "▄", (1, 1): "█"}[on]
            elif t == b == (0, 0, 0):
                out += "\x1b[0m "
            elif b == (0, 0, 0):
                out += "\x1b[0;38;2;%d;%d;%dm▀" % t
            else:
                out += "\x1b[38;2;%d;%d;%d;48;2;%d;%d;%dm▀" % (t + b)
        lines.append(out.rstrip() + ("" if mode == "mono" else "\x1b[0m"))
    while lines and not lines[-1].replace("\x1b[0m", "").strip():
        lines.pop()
    open(dst, "w", encoding="utf-8").write("\n".join(lines) + "\n")

if __name__ == "__main__":
    cmd, a = sys.argv[1], sys.argv[2:]
    if cmd == "peres":
        peres(a[0], a[1], set(a[2].split(",")))
    elif cmd == "icons":
        icons(a[0], a[1], {int(s) for s in a[2].split(",")})
    elif cmd == "wave":
        wave(a[0], a[1], a[2])
    elif cmd == "strip":
        strip(a[0], a[1], a[2])
    elif cmd == "msstyles":
        msstyles(a[0], a[1])
    elif cmd == "xcursor":
        xcursor(a[0], a[1], a[2])
    elif cmd == "halfblock":
        halfblock(a[0], a[1], a[2])
    else:
        sys.exit(__doc__)
