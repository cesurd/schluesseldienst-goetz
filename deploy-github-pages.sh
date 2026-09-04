#!/bin/bash
# ============================================================
# Vorschau-Deploy nach https://github.com/cesurd/schluesseldienst-goetz
# → live auf https://cesurd.github.io/schluesseldienst-goetz/
#
# Baut aus dem Projektordner eine BEREINIGTE Kopie. Nie den
# Quellordner direkt pushen, er enthält Dinge, die öffentlich
# nichts zu suchen haben:
#   • STAND-UND-UEBERGABE.md  (Preise, Rechnungsnummer, die
#     Zuschlags-Rechtsfrage, Kritik am Vorbetreuer)
#   • DEPLOY-NOTIZEN.md       (KAS-Umzugsweg)
#   • HTML-Kommentar im Impressum: „VOR GO-LIVE MIT PATRICK
#     GÖTZ / STEUERBERATER KLÄREN" — verrät die Lücke
#   • sitemap.xml / robots.txt / llms.txt / .htaccess
#     (zeigen alle auf die echte Domain)
#
# Außerdem:
#   • wurzel-relative Pfade umschreiben — auf Pages liegt die
#     Seite unter /schluesseldienst-goetz/, nicht im Host-Root.
#     TIEFENABHÄNGIG: Ortsseiten brauchen ../
#   • noindex setzen, damit die Vorschau nicht gegen die echte
#     Domain antritt
#
# Aufruf: bash deploy-goetz-pages.sh
# ============================================================
set -euo pipefail

SRC="/Users/denniscesur/Library/CloudStorage/GoogleDrive-dennis.cesur2@gmail.com/Meine Ablage/01 Rex Fortis/01 Websites/Goetz-Schluesseldienst"
BUILD="${TMPDIR:-/tmp}/goetz-gh-build"
REPO="https://github.com/cesurd/schluesseldienst-goetz.git"

echo "→ Kopie bauen in $BUILD"
rm -rf "$BUILD" && mkdir -p "$BUILD"
rsync -a \
  --exclude '*.md' --exclude '.htaccess' --exclude 'sitemap.xml' \
  --exclude 'robots.txt' --exclude 'llms.txt' \
  --exclude '.DS_Store' --exclude '.git' --exclude '_alt-favicons' --exclude '_herkunft-ungeklaert' --exclude 'og-image-vorlage.html' \
  "$SRC/" "$BUILD/"

python3 - "$BUILD" <<'PY'
import re, sys, pathlib
root = pathlib.Path(sys.argv[1])
VORSCHAU = 'https://cesurd.github.io/schluesseldienst-goetz/'
kom = pfade = idx = umgebogen = 0
for p in sorted(root.rglob('*.html')):
    tiefe = len(p.relative_to(root).parts) - 1
    pre = '../' * tiefe
    s = orig = p.read_text(encoding='utf-8')

    # 1) sämtliche HTML-Kommentare raus (auch der Impressum-Hinweis)
    s, n = re.subn(r'\n?[ \t]*<!--.*?-->', '', s, flags=re.S); kom += n

    # 2) wurzel-relative Pfade tiefenabhängig umschreiben
    def href_root(m):
        return f'{m.group(1)}="{pre if pre else "./"}"'
    s, a = re.subn(r'(href|src)="/"', href_root, s)
    def href_pfad(m):
        return f'{m.group(1)}="{pre}{m.group(2)}"'
    s, b = re.subn(r'(href|src)="/(?!/)([^"]*)"', href_pfad, s)
    def srcset(m):
        inner = re.sub(r'(^|,\s*)/(?!/)', lambda mm: mm.group(1) + pre, m.group(1))
        return f'srcset="{inner}"'
    s, c = re.subn(r'srcset="([^"]*)"', srcset, s)
    pfade += a + b + c

    # 3) Absolute Verweise auf die echte Domain umbiegen.
    #    og:image, og:url und canonical zeigten auf schluesseldienst-goetz.de —
    #    dort läuft noch WordPress, die Datei liefert 404. WhatsApp und Co. fanden
    #    also kein Vorschaubild und sind aufs Favicon zurückgefallen.
    s, e = re.subn(r'https://schluesseldienst-goetz\.de/', VORSCHAU, s); umgebogen += e

    # 4) Vorschau darf nicht indexiert werden
    if 'name="robots"' not in s:
        s, d = re.subn(r'(<meta name="viewport"[^>]*>)',
                       r'\1\n<meta name="robots" content="noindex,nofollow">', s, count=1)
        idx += d

    s = re.sub(r'\n{3,}', '\n\n', s)
    if s != orig:
        p.write_text(s, encoding='utf-8')

(root / '.nojekyll').write_text('', encoding='utf-8')
print(f'   {kom} Kommentare entfernt, {pfade} Pfade umgeschrieben, {umgebogen} Domainverweise umgebogen, {idx}× noindex gesetzt')
PY

echo "→ Sicherheitsnetz"
fail=0
if grep -rq '<!--' "$BUILD" --include='*.html'; then echo "  ✗ HTML-Kommentar im Build"; fail=1; fi
if grep -rqE '(href|src)="/[^/]' "$BUILD" --include='*.html'; then echo "  ✗ wurzel-relativer Pfad im Build"; fail=1; fi
if grep -rqiE 'steuerberater|vorbetreuer|zuschlag|abmahn|go-live|übergabe' "$BUILD" --include='*.html'; then
  echo "  ✗ interne Formulierung im Build"; fail=1; fi
if grep -rq 'schluesseldienst-goetz.de' "$BUILD" --include='*.html'; then
  echo "  ✗ Verweis auf die echte Domain im Build (og:image/canonical laufen dort ins Leere)"; fail=1; fi
# Sollzahl = Seiten im Quellordner. NICHT aus der sitemap.xml ableiten: Impressum und
# Datenschutz stehen auf noindex und gehören deshalb nicht in die Sitemap (korrigiert
# am 03.09.2026), die Zahlen sind also absichtlich verschieden.
SOLL=$(find "$SRC" -name 'index.html' -not -path '*/.git/*' | wc -l | tr -d ' ')
MIT=$(grep -rl 'noindex' "$BUILD" --include='*.html' | wc -l | tr -d ' ')
ALLE=$(find "$BUILD" -name '*.html' | wc -l | tr -d ' ')
if [ "$MIT" != "$ALLE" ] || [ "$ALLE" != "$SOLL" ]; then
  echo "  ✗ noindex auf $MIT von $ALLE Seiten (Quellordner hat $SOLL Seiten)"; fail=1; fi
# Sitemap darf keine noindex-Seite nennen – das meldet die Search Console als Fehler.
for U in impressum datenschutz; do
  if grep -q "schluesseldienst-goetz.de/$U/" "$SRC/sitemap.xml"; then
    echo "  ✗ Sitemap nennt /$U/, die Seite steht aber auf noindex"; fail=1; fi
done
if ls "$BUILD"/*.md >/dev/null 2>&1; then echo "  ✗ Markdown im Build"; fail=1; fi
[ "$fail" = "1" ] && { echo "ABBRUCH"; exit 1; }
echo "  ✓ sauber"

cd "$BUILD"
git init -b main -q
git add -A
git -c user.name="Dennis Cesur" -c user.email="dennis.cesur2@gmail.com" \
    commit -q -m "Schlüsseldienst Götz — Website-Entwurf (Vorschau, noindex)"
git remote add origin "$REPO"
git push -f -u origin main -q
echo "→ gepusht"
