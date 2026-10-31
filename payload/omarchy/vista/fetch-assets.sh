#!/usr/bin/env bash
# fetch-assets.sh [--iso PATH | --from-iso [--keep-iso]] -- download Microsoft's
# original Windows Vista files (visual style, shell art, fonts, sounds,
# wallpapers, cursors, Sidebar gadgets) and the B00merang Windows Vista GTK
# theme, for personal use on this machine only.
#
# Everything lands in omarchy/vista/assets/ (git-ignored; never commit it);
# fonts go to ~/.local/share/fonts/vista, the GTK theme to
# ~/.local/share/themes/Windows Vista, the pointers to
# ~/.local/share/icons/windows-vista-cursors. User-level only, no sudo.
#
# Source: Windows Vista Business SP2 (6.0.6002.18005), the MSDN x86 DVD, whose
# install.wim an archive.org item holds unpacked inside a zip; archive.org
# serves each file of it on its own, so only the files actually used are
# downloaded (see ASSETS.md for provenance and checks).
#   --iso PATH   take the same files from a Vista SP2 DVD image you have
#                (7z + wimlib-imagex); the sha256 pins below still apply
#   --from-iso   download that DVD image (3.24 GB, resumable, asks first),
#                verify it, use it, delete it (unless --keep-iso)
#
# Trust model: every file is pinned by sha256 (trust-on-first-use, pinned
# 2026-10-31), and so is every derived file or tree. A mismatch is fatal for
# that file and the run exits non-zero. Downloads are data: they are unpacked
# into fresh empty directories, PE files are only *parsed* (vistatool.py),
# and nothing downloaded is ever executed. Idempotent: files already present
# with the right hash are not fetched again.
set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ASSETS=$HERE/assets
DATA=${XDG_DATA_HOME:-$HOME/.local/share}
UA='ocko-omarchy-vista-fetch/0.1 (personal use)'
BASE='https://archive.org/download/en_windows_vista_sp2_x86_dvd_342266.zip/en_windows_vista_sp2_x86_dvd.zip/sources%2Finstall%2F'
ISO_URL='https://archive.org/download/en_windows_vista_sp2_x86_dvd_342266/en_windows_vista_sp2_x86_dvd_342266.iso'
ISO_SIZE=3243413504
ISO_SHA1=25ad9a776503e6a583bec07879dbcc5dfd20cd6e   # the published MSDN sha1
ISO_CACHE=${XDG_CACHE_HOME:-$HOME/.cache}/omarchy-windows-vista

ISO="" FROM_ISO=0 KEEP_ISO=0
while (($#)); do
    case $1 in
        --iso) ISO=$(realpath "$2"); shift ;;
        --from-iso) FROM_ISO=1 ;;
        --keep-iso) KEEP_ISO=1 ;;
        *) echo "usage: fetch-assets.sh [--iso PATH | --from-iso [--keep-iso]]" >&2; exit 2 ;;
    esac
    shift
done

missing=()
for t in curl sha256sum python3 fc-cache bsdtar realpath magick; do command -v "$t" >/dev/null || missing+=("$t"); done
if [[ -n $ISO ]] || ((FROM_ISO)); then
    for t in 7z wimlib-imagex sha1sum; do command -v "$t" >/dev/null || missing+=("$t"); done
fi
if ((${#missing[@]})); then
    echo "fetch-assets: missing tools: ${missing[*]} (pacman: curl coreutils python fontconfig libarchive imagemagick; for --iso also 7zip wimlib)" >&2
    exit 2
fi

WORK=$(mktemp -d "${TMPDIR:-/tmp}/vista-fetch.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
VT=(python3 -I "$HERE/vistatool.py")
failures=() verified=0 fetched=0

# ── Microsoft's files: dest (under assets/) | sha256 | path in install.wim ──
FILES=$(cat <<'EOF'
account-pictures/guest.bmp|40015814487b93a8372f33284d45586739a4a1e9d2b7961ab8c6d4d9561d10cb|ProgramData/Microsoft/User Account Pictures/guest.bmp
account-pictures/user.bmp|492c966bd8984671ebf8a58bbb2358053e888e57ad7dbb9b54416105a6548c65|ProgramData/Microsoft/User Account Pictures/user.bmp
account-pictures/usertile10.bmp|21bccb07ec38e463001a91cf8e9a580cc65c2744a7b111395456f3693b7339af|ProgramData/Microsoft/User Account Pictures/Default Pictures/usertile10.bmp
account-pictures/usertile11.bmp|c970625155f463da15c38ccba5d6420b68b24b2fea042b37c06cf332a02420d3|ProgramData/Microsoft/User Account Pictures/Default Pictures/usertile11.bmp
account-pictures/usertile12.bmp|24519419525cbc9f792b8448af6b9a9a885e154505518092959e1b2a90e14247|ProgramData/Microsoft/User Account Pictures/Default Pictures/usertile12.bmp
account-pictures/usertile2.bmp|1a01d6c09311e1c1b12bc6fcefd998141f3a6c02ebd53859fd5d6d5a740739ab|ProgramData/Microsoft/User Account Pictures/Default Pictures/usertile2.bmp
account-pictures/usertile3.bmp|d35c9f17a24620d016dade1399fa333021970b3a18a56d0b472f13a2c876324b|ProgramData/Microsoft/User Account Pictures/Default Pictures/usertile3.bmp
account-pictures/usertile4.bmp|f0731d8a6ad81d11859133d7aba3761cb76a6daa0a097401730f058efdce6b31|ProgramData/Microsoft/User Account Pictures/Default Pictures/usertile4.bmp
account-pictures/usertile5.bmp|c5e4352c70a26b50b60e498d97dd7959c44d9feec3e065079b883886b9590bf1|ProgramData/Microsoft/User Account Pictures/Default Pictures/usertile5.bmp
account-pictures/usertile6.bmp|406343e5ca625d9c6c8630b62ee6e2028475e190c35f201cb83580e3692d7799|ProgramData/Microsoft/User Account Pictures/Default Pictures/usertile6.bmp
account-pictures/usertile7.bmp|fbc800f7a8708ce3372e63b611ade28ae372c169f3328200bcbd0b5dc1f48bff|ProgramData/Microsoft/User Account Pictures/Default Pictures/usertile7.bmp
account-pictures/usertile8.bmp|6bf1feb2b35feb0327ddc8c6f8b05c072a089be59e160f41da74aaf15d57d3eb|ProgramData/Microsoft/User Account Pictures/Default Pictures/usertile8.bmp
account-pictures/usertile9.bmp|84d34f5b358f39f9ac856f14b615417cb9f420d6be9aa1f51cf8d59a41a03151|ProgramData/Microsoft/User Account Pictures/Default Pictures/usertile9.bmp
binaries/aero.msstyles.mui|b8e9a93c06107637864af833a78230a43808d6f822f16e218bbe921e757012a7|Windows/Resources/Themes/Aero/en-US/aero.msstyles.mui
binaries/aero.msstyles|ac25fdb203de823e36112296d34244122cdd433aa04d820d4ddd6556ac8578bd|Windows/Resources/Themes/Aero/aero.msstyles
binaries/aero.theme|915ac95d45d3b8000609b8fbaecb9116e9bd95441863b736e5a55968180e1315|Windows/Resources/Themes/aero.theme
binaries/authui.dll.mui|7aea819da569997345a4d966254324020bc08ad0ea60e16ddfb0a1f454e170d9|Windows/System32/en-US/authui.dll.mui
binaries/authui.dll|6c5d9503e587904f5207e0ab470325dbea0c32eb6693521de669df2d0bd935d4|Windows/System32/authui.dll
binaries/basebrd.dll|26a2f8d3719c028a307b053044a9ff30df4e7b7ce99f9ad47090c4f21b8c248b|Windows/Branding/Basebrd/basebrd.dll
binaries/batmeter.dll|400cd49d44643cc72129a918b2e2b4fedb5dd26a9709d7a686b01432f73f0474|Windows/System32/batmeter.dll
binaries/bthprops.cpl.mui|ebd475c080f78485845b1e0ac2ee3403083f6009e23cd4b786c0961611c8b98c|Windows/System32/en-US/bthprops.cpl.mui
binaries/bthprops.cpl|fcb7316fba1f37eaa0036ce6a075c55fbbcb58c4444b053963e540517e95d636|Windows/System32/bthprops.cpl
binaries/consent.exe.mui|b20bedcbafe497b134bc8073ca291708f4e63790376dae71c7986559424ea19d|Windows/System32/en-US/consent.exe.mui
binaries/consent.exe|a77dd8a8d8a562b54321c60812c7c77387e88cacbfa4e8911f1f7e010410a1be|Windows/System32/consent.exe
binaries/desk.cpl.mui|bba42b3b16cde3824310dbad4de1238e10800e57afbeb8f9fb1a7eba26be54b7|Windows/System32/en-US/desk.cpl.mui
binaries/desk.cpl|cb8f021c0e98a1d163c0323feb17ef1c2c42a1b5da447bae40c317bfdeddf272|Windows/System32/desk.cpl
binaries/explorer.exe|135dd05678c8997b45982d77298dbdd98061c9d4fe43d77866846012eb061a04|Windows/explorer.exe
binaries/imageres.dll|6910253aa5dfd7e2656c65b7227e7d546648d6c55600552d79fa275d0331aa00|Windows/System32/imageres.dll
binaries/mmsys.cpl.mui|075f59563bc08533ad29ba9b5661eb69627920393933a492dcfa8b91a662d790|Windows/System32/en-US/mmsys.cpl.mui
binaries/mmsys.cpl|53c4804da9b5a233c2549ea12749f5ad5da1b132ff761e9ab4b43d134861ef3d|Windows/System32/mmsys.cpl
binaries/netshell.dll.mui|14e6ac7960be57e4c710adb0a5ca44da046220a12ef287d632dfd9de7aa120fd|Windows/System32/en-US/netshell.dll.mui
binaries/netshell.dll|63aa9ba292f5a62c0b6c668be27e4b0bf1761cd5d961d405caede2dc7c54a2e2|Windows/System32/netshell.dll
binaries/pnidui.dll|603eca45f49420ee4f8549fb11c6cb814990e0a562786e6deb3af434a1d42e39|Windows/System32/pnidui.dll
binaries/shell32.dll.mui|7c770672d94e7ee8b1abf2111063d06a21d211486dca5415d96b33fbb29dc5b3|Windows/System32/en-US/shell32.dll.mui
binaries/shell32.dll|83767e4b0bba094c90fedfd22295204e0272c5a188cb241a308365555e2089d2|Windows/System32/shell32.dll
binaries/sidebar.exe.mui|9b7f8f8edb8309d769d6cad224813d2f1eee09e0f5805227bbe3ec73ad30ccd3|Program Files/Windows Sidebar/en-US/Sidebar.exe.mui
binaries/sidebar.exe|54712a4fa296ae28cf834f90b77b2eeb69020e3d5b5cf24674bd8daca25195b9|Program Files/Windows Sidebar/sidebar.exe
binaries/sndvol.exe.mui|1ecf53c8a2ea509ae9846fda7540e670efe30203c62b9b476d5d3f52783d54a5|Windows/System32/en-US/sndvol.exe.mui
binaries/sndvol.exe|0a5372d1430332931f9466fed31e54cca556cb3695db59437e064d40af3b3ba8|Windows/System32/SndVol.exe
binaries/sndvolsso.dll|a1ce545dbb8983bd71c82fac1c3f2633e571fac7efddd8e99e73c7a308a31861|Windows/System32/SndVolSSO.dll
binaries/themecpl.dll.mui|a1692334269b577775730e932055ef0a1d6c507b975f951090a0d4de986ec164|Windows/System32/en-US/themecpl.dll.mui
binaries/themecpl.dll|7a0fef400fdae96a786c273abafa3623e853f4fece12310e45f765983c62137f|Windows/System32/themecpl.dll
binaries/timedate.cpl|a05dfcf03c424dea2d3f0624465a54e4a7d7af9b9c914d938ea2a5f21ee38113|Windows/System32/timedate.cpl
binaries/user32.dll|d9f989669eb0aaf384aa5462dd632999bf9c5a6bdb75c4f8857a6e9bdbe82b64|Windows/System32/user32.dll
binaries/van.dll.mui|d5ecf3c7f9b634554020ab36235e6f8f5986dbf8b81a094650a347a12c349cda|Windows/System32/en-US/VAN.dll.mui
binaries/van.dll|ced99ad3df223893dfc13614785831a08e6fe16a45324dc30e17ceb2fda3b27d|Windows/System32/VAN.dll
binaries/wlanpref.dll.mui|9ae95b6d2da342e29a143f784a3548c5d82a2a15f6244f49b5862508b97d872c|Windows/System32/en-US/wlanpref.dll.mui
cursors/aero_arrow.cur|8e4089397e0eb4115f0da06c85abb26d9e8e8e1e242f2d41d813dc70fd104f3d|Windows/Cursors/aero_arrow.cur
cursors/aero_arrow_l.cur|af858d0c7b63b10ee89a61e6354198d57da31f024bf8543da09fc45b31dab6dd|Windows/Cursors/aero_arrow_l.cur
cursors/aero_arrow_xl.cur|4b687977abeeb3a3ca88b2f577ef893a82f72c71b0a188c03f73cc4f250d85ba|Windows/Cursors/aero_arrow_xl.cur
cursors/aero_busy.ani|52f9fc3a6448b7cacafeb522811be956e4fb528f2c4bc32100787fc5301e26e0|Windows/Cursors/aero_busy.ani
cursors/aero_busy_l.ani|e9cc1398584e4af96139bc3a13003cc4ecccc366c2cabca0b208b16d6aeed415|Windows/Cursors/aero_busy_l.ani
cursors/aero_busy_xl.ani|e9cc1398584e4af96139bc3a13003cc4ecccc366c2cabca0b208b16d6aeed415|Windows/Cursors/aero_busy_xl.ani
cursors/aero_ew.cur|093c36f1baa94b49498b173a197a99c72835381aa0b1823ae669eb19adfcc430|Windows/Cursors/aero_ew.cur
cursors/aero_ew_l.cur|59f16c4e3f6263e9e4fb3351b0a7f9015238a674f041b106041ffb2a36f18b29|Windows/Cursors/aero_ew_l.cur
cursors/aero_ew_xl.cur|67682e1d4bf1c26d3c846f871ee1aeda0587871a0159cebd994d03773b29a00c|Windows/Cursors/aero_ew_xl.cur
cursors/aero_helpsel.cur|baf46f370b382b35dc43b33494263c21b31198421790353ac57303a3dcce696f|Windows/Cursors/aero_helpsel.cur
cursors/aero_helpsel_l.cur|c71d4a95602d31bedf41a149a22dec9718e626ce0dad56ff202fa34bb0addc8c|Windows/Cursors/aero_helpsel_l.cur
cursors/aero_helpsel_xl.cur|d15634d648ff04b3d4101f316e99c71dc8b32ab220f6e9e3222e3f66dfdac637|Windows/Cursors/aero_helpsel_xl.cur
cursors/aero_link.cur|eeb61c78c583b09597a14de97c77c90bbecb3d9af9ed0b630f84a0bd35f2e56c|Windows/Cursors/aero_link.cur
cursors/aero_link_l.cur|bbaf75819af18b5be6b883d899e29166d42141a84b8f82da33165e687edd4c84|Windows/Cursors/aero_link_l.cur
cursors/aero_link_xl.cur|e94e815ce348e0714f27e317f3588a9ca68c4410232793045fccc3b7176d7e76|Windows/Cursors/aero_link_xl.cur
cursors/aero_move.cur|54181c6b555396ba623781663dc20388edf85cfc49a7d86466dbb937dcead4b3|Windows/Cursors/aero_move.cur
cursors/aero_move_l.cur|c6f41b308db8cca9127fb7fc0e74e6c4b34f05187fd48fd049c11c7dd73dae83|Windows/Cursors/aero_move_l.cur
cursors/aero_move_xl.cur|c298d5ad20c4bee1c111a52c46c98b3c01ffad9585e776af8edb20445a3657cc|Windows/Cursors/aero_move_xl.cur
cursors/aero_nesw.cur|de8ca70a6bd0e8738200cfe5a9d2e50514c8274e39e9939493726cc307ea7df4|Windows/Cursors/aero_nesw.cur
cursors/aero_nesw_l.cur|0e53676e60ea8b0bebfdba4187dd106df99a299b831de8acaec116a77547ec0c|Windows/Cursors/aero_nesw_l.cur
cursors/aero_nesw_xl.cur|28e530719ba6a575c8719ea8a7493778d179bc237def20be9fc72dba03281b04|Windows/Cursors/aero_nesw_xl.cur
cursors/aero_ns.cur|ae87e1be2012a8d22db328bec839cc01705776df4a8668a373d2d7efd918cc09|Windows/Cursors/aero_ns.cur
cursors/aero_ns_l.cur|20ed0b6fbb610eadaa94fc4f70fe0336f44d6742ce72f3db7307bb3723dd06b2|Windows/Cursors/aero_ns_l.cur
cursors/aero_ns_xl.cur|3d75464a9d39bad961026b4663a18534a6037d5f449af585eebcd4df58218dfb|Windows/Cursors/aero_ns_xl.cur
cursors/aero_nwse.cur|26ba676103297f4fe9dba4d49238be80b1a7dbb1e869ec1a0986c6e7afdfd07b|Windows/Cursors/aero_nwse.cur
cursors/aero_nwse_l.cur|29896c1756281ccd062f36e1fcd10c5975433482e1eb7f085dceae2a8e1538bc|Windows/Cursors/aero_nwse_l.cur
cursors/aero_nwse_xl.cur|29fffb9024cd53755e810abe29ae5f8cf92dfcadba9872eb40281aaef938af22|Windows/Cursors/aero_nwse_xl.cur
cursors/aero_pen.cur|7e99a350ddaf9d1bf939f26a0a365e6677b0770ef70332fc478729473598c46a|Windows/Cursors/aero_pen.cur
cursors/aero_pen_l.cur|3b7bec876c4d51d5e11dba168e9a2df65f80797fe2db2ca5d70102c46c0262a2|Windows/Cursors/aero_pen_l.cur
cursors/aero_pen_xl.cur|90e20d3fee155bdb92788c726b814eb73a31681edb2b6638666885583db385e1|Windows/Cursors/aero_pen_xl.cur
cursors/aero_unavail.cur|85e0864f563670b38da0f54e069967816bb885a1a535c349f94730f949c00ec1|Windows/Cursors/aero_unavail.cur
cursors/aero_unavail_l.cur|61ca0d638ced1278344edb98c59b5c4d512fea17f1b6c4dfe1ba5069bd7ebe68|Windows/Cursors/aero_unavail_l.cur
cursors/aero_unavail_xl.cur|3ba82e28158c115c3585081fdeb0755ec5e4efcc8c69c395095ef05de2d77f64|Windows/Cursors/aero_unavail_xl.cur
cursors/aero_up.cur|7b39802b5903e24a9fc3c82187ef6dae5df72127a6a05b63ad7fa0c17b3969d4|Windows/Cursors/aero_up.cur
cursors/aero_up_l.cur|416fc100014b4709912db74fb0a990eeaec632b8f80a07575e0a46752b9946f5|Windows/Cursors/aero_up_l.cur
cursors/aero_up_xl.cur|b8c8d2d9e4df4918c8e6c1771408c6034790ec9fe5475f4a59dd53ca44085c51|Windows/Cursors/aero_up_xl.cur
cursors/aero_working.ani|d5d304c4672cfcc81bb8fcab7c174f8377208b41b1556235fa68d8bfefe39b73|Windows/Cursors/aero_working.ani
cursors/aero_working_l.ani|8c679f9a6adf2be77016768477a1879c8a600817f1ee45fe5b23d78fc2f7c358|Windows/Cursors/aero_working_l.ani
cursors/aero_working_xl.ani|1dbc83ebaf3153238bcfb22dae0531fcb1bbb4545ea9ed55fc24ac48842e7e42|Windows/Cursors/aero_working_xl.ani
fonts/consola.ttf|2a65227ee5b4eaa896bec8a150d90d770ea4f2f59a2ef240eb6ae614951d3d77|Windows/Fonts/consola.ttf
fonts/consolab.ttf|321298ddbc374e4b3b7e7f1ed27eda8f9bd4c6d4fc2d140e307cae5ac9458bea|Windows/Fonts/consolab.ttf
fonts/consolai.ttf|8f5256134cd1d931038f9fd54c99f311eca41e2e54515a25eda02a6aa5cd5705|Windows/Fonts/consolai.ttf
fonts/consolaz.ttf|ea09e71bad202dc0caf0454a833224f8d179aa7a2ad71f82ba3d9677e3e05537|Windows/Fonts/consolaz.ttf
fonts/segoeui.ttf|f0ba8bd5350f7f552965b0d6a8cd831131eb115224b42835b341dc971f30bf33|Windows/Fonts/segoeui.ttf
fonts/segoeuib.ttf|d9558e4be46ec9bf31d150f5d170ce046c0b0d987b993ef8cbc7445f964ab6b3|Windows/Fonts/segoeuib.ttf
fonts/segoeuii.ttf|b29122a5bddf449f154f2fdb237d27f4b3c736144f7df0321bf7b6f2620ab5c2|Windows/Fonts/segoeuii.ttf
fonts/segoeuiz.ttf|6675cd17be1bf753b11aa53ad64629e5b27d4cec7fb2b7099fe2f5e5cd0841d4|Windows/Fonts/segoeuiz.ttf
gadgets/CPU.Gadget/drag.png|0a9ebda9d4d09b0d87e27d6087fd9c0df1efec0812c9f71d440c0ac1c8a79045|Program Files/Windows Sidebar/Gadgets/CPU.Gadget/drag.png
gadgets/CPU.Gadget/icon.png|67cbebd899c38ca451de29a629d84a6b442061f6435495a3f759b5ec88c20057|Program Files/Windows Sidebar/Gadgets/CPU.Gadget/icon.png
gadgets/CPU.Gadget/images/back.png|2e252434d4bb3c3ac6104aee3df0cf2e0e491029cfa0ac1c170f4c6cd337834f|Program Files/Windows Sidebar/Gadgets/CPU.Gadget/images/back.png
gadgets/CPU.Gadget/images/back_lrg.png|16d0cc3bee8ac673475ea130d473b03c2c688deb0447ec76a915913519a08a8d|Program Files/Windows Sidebar/Gadgets/CPU.Gadget/images/back_lrg.png
gadgets/CPU.Gadget/images/dial.png|3df2f22a3165fae08ba5dbd23c3907f569a320f1a6268dbc18bfe01da6bff8c8|Program Files/Windows Sidebar/Gadgets/CPU.Gadget/images/dial.png
gadgets/CPU.Gadget/images/dial_lrg.png|87ee5b117817a50ce26288d111d83c6fed9d07612410f856b925c7840d17cbdc|Program Files/Windows Sidebar/Gadgets/CPU.Gadget/images/dial_lrg.png
gadgets/CPU.Gadget/images/dial_lrg_sml.png|8d1b37c8740bb9f6f5fcadf96937f18152376cd04be08dd58791e17c485c312c|Program Files/Windows Sidebar/Gadgets/CPU.Gadget/images/dial_lrg_sml.png
gadgets/CPU.Gadget/images/dial_sml.png|c68ee88daf50eaec0938639b6c15139c5adbcfa0e969aaf79598f2e9a375931b|Program Files/Windows Sidebar/Gadgets/CPU.Gadget/images/dial_sml.png
gadgets/CPU.Gadget/images/dialdot.png|ce4f584ec4c38a0e808523f353a0d1e914ce14793666a2942a2c26d4b1ddc4f7|Program Files/Windows Sidebar/Gadgets/CPU.Gadget/images/dialdot.png
gadgets/CPU.Gadget/images/dialdot_lrg.png|7c58dc9d999de88058bf0b9aaee8649a13cba64c6c1531e9878ecd2b58ffd0a8|Program Files/Windows Sidebar/Gadgets/CPU.Gadget/images/dialdot_lrg.png
gadgets/CPU.Gadget/images/glass.png|b68456d14194e5d9660c6622dfac3688627a870c5ff74bef1f44ab78ad925080|Program Files/Windows Sidebar/Gadgets/CPU.Gadget/images/glass.png
gadgets/CPU.Gadget/images/glass_lrg.png|e9f865ec8acd0deb7d004ca8dc6a9eb17e8e1a46892509a913132d6e2fb65dc0|Program Files/Windows Sidebar/Gadgets/CPU.Gadget/images/glass_lrg.png
gadgets/CPU.Gadget/logo.png|04ce251b18a31e2425d5358c4bce3f075c9e507699fe509d9f17e9b8ec6d5ea9|Program Files/Windows Sidebar/Gadgets/CPU.Gadget/logo.png
gadgets/Clock.Gadget/drag.png|c39a22982f7507278946047338c1b74706c7a7ddb7519740ccb234bd66dd4f5a|Program Files/Windows Sidebar/Gadgets/Clock.Gadget/drag.png
gadgets/Clock.Gadget/icon.png|8b592cfce944a3421825cece57045e8b99459c34d8815094ab995df07135b751|Program Files/Windows Sidebar/Gadgets/Clock.Gadget/icon.png
gadgets/Clock.Gadget/images/cronometer.png|b7ca6089d134919c25556de1fd2e5ebb28e40ea0623a155b9ce4471883b39575|Program Files/Windows Sidebar/Gadgets/Clock.Gadget/images/cronometer.png
gadgets/Clock.Gadget/images/cronometer_dot.png|a85e6876b5d44e4b6f2ed8e8f2b2469887c04897bd11a5cf2a3c89f10a921522|Program Files/Windows Sidebar/Gadgets/Clock.Gadget/images/cronometer_dot.png
gadgets/Clock.Gadget/images/cronometer_h.png|bfeff378a649ef914011827319d5cf2870b833e76da7655a0aee77071b79d289|Program Files/Windows Sidebar/Gadgets/Clock.Gadget/images/cronometer_h.png
gadgets/Clock.Gadget/images/cronometer_highlights.png|d4d9ea23f43fa36db7132ae4cbf4707a839abe6c3e8103646bc85759eed63344|Program Files/Windows Sidebar/Gadgets/Clock.Gadget/images/cronometer_highlights.png
gadgets/Clock.Gadget/images/cronometer_m.png|70b39b8f633337a582567ab392f109c94649df74f0f2cd1b46078eb62b52252f|Program Files/Windows Sidebar/Gadgets/Clock.Gadget/images/cronometer_m.png
gadgets/Clock.Gadget/images/cronometer_s.png|21256abfd1baf7fce100cc5b54d9182ac2fd9a8b301b2ebb1ad67eddcca6e5e5|Program Files/Windows Sidebar/Gadgets/Clock.Gadget/images/cronometer_s.png
gadgets/Clock.Gadget/images/cronometer_settings.png|d04a7be416e33a3105e677007ab4433b87922c7c34ab229862548173be419fbc|Program Files/Windows Sidebar/Gadgets/Clock.Gadget/images/cronometer_settings.png
gadgets/Clock.Gadget/images/diner.png|4a898ff3d7ec318e69e1179bcc10007a450ec0db04b15c8ced458a55831abf81|Program Files/Windows Sidebar/Gadgets/Clock.Gadget/images/diner.png
gadgets/Clock.Gadget/images/diner_dot.png|399cd4e564d33e2443e4497c072c44987694e01d386a1e89601c1f85b812b0fd|Program Files/Windows Sidebar/Gadgets/Clock.Gadget/images/diner_dot.png
gadgets/Clock.Gadget/images/diner_h.png|049379ef6f791a562fcd675d175d097f3b0b3f5a25fa47a6717f2037baead903|Program Files/Windows Sidebar/Gadgets/Clock.Gadget/images/diner_h.png
gadgets/Clock.Gadget/images/diner_m.png|6d96ed9c3923ff0de8251f0eddd6dde4c0fb977cef143c048f4be629d5ea41b9|Program Files/Windows Sidebar/Gadgets/Clock.Gadget/images/diner_m.png
gadgets/Clock.Gadget/images/diner_s.png|d1d1f2e108e9b45033e1b89fe9da3ed8cb02b00cf520776ce1e5f02357e32b00|Program Files/Windows Sidebar/Gadgets/Clock.Gadget/images/diner_s.png
gadgets/Clock.Gadget/images/diner_settings.png|e46ca5ab0cd5df588c96b5ddab0c6170a4259bd2f35c2c21266d53b30f5c2525|Program Files/Windows Sidebar/Gadgets/Clock.Gadget/images/diner_settings.png
gadgets/Clock.Gadget/images/flower.png|1900944836732134642f111163497cfde169036c04cf968841b440bf4086311d|Program Files/Windows Sidebar/Gadgets/Clock.Gadget/images/flower.png
gadgets/Clock.Gadget/images/flower_dot.png|96d7ef574b3d107127b77e34f6e772057d67d31750dd986a9878d28c6f9908cc|Program Files/Windows Sidebar/Gadgets/Clock.Gadget/images/flower_dot.png
gadgets/Clock.Gadget/images/flower_h.png|130e4f18b6679739540397e7b4f4ad0737d63f34f28e690d58fb9977ad566a97|Program Files/Windows Sidebar/Gadgets/Clock.Gadget/images/flower_h.png
gadgets/Clock.Gadget/images/flower_m.png|c3b3de87a3b5bf1a0febbddc7afa8ab41644bf18a2bcb040cc80a281de195adc|Program Files/Windows Sidebar/Gadgets/Clock.Gadget/images/flower_m.png
gadgets/Clock.Gadget/images/flower_s.png|e5bf859bbb3e898dd4b08a68ecfdaa3a81c714a359539e801567d4d51a53d578|Program Files/Windows Sidebar/Gadgets/Clock.Gadget/images/flower_s.png
gadgets/Clock.Gadget/images/flower_settings.png|5ed4692d50bedf4656dc32be03eee63103b1174d99492f00211ecb89546d0df6|Program Files/Windows Sidebar/Gadgets/Clock.Gadget/images/flower_settings.png
gadgets/Clock.Gadget/images/modern.png|0d5f17fc27eb728eed828c536f3f4a19328cfed141331cf2966673e44d19bc3d|Program Files/Windows Sidebar/Gadgets/Clock.Gadget/images/modern.png
gadgets/Clock.Gadget/images/modern_dot.png|8ef4912f720a00d403e2629d554b719d27a9945c8ee735fd162cbc87357b6d0f|Program Files/Windows Sidebar/Gadgets/Clock.Gadget/images/modern_dot.png
gadgets/Clock.Gadget/images/modern_h.png|1e13043c01852a7d9884db1f6ef9de288be5a22be17a1bab10f0acbb2101260d|Program Files/Windows Sidebar/Gadgets/Clock.Gadget/images/modern_h.png
gadgets/Clock.Gadget/images/modern_m.png|fb12edf1e24c3399015440f9baed8f384feff0cf273de40f6bb5a083de4854cb|Program Files/Windows Sidebar/Gadgets/Clock.Gadget/images/modern_m.png
gadgets/Clock.Gadget/images/modern_s.png|ebe0fd9b195d1875b9b98c9a256b6632d3102841e044349cb8d26db55d67f0e9|Program Files/Windows Sidebar/Gadgets/Clock.Gadget/images/modern_s.png
gadgets/Clock.Gadget/images/modern_settings.png|0e1e1a57b2b306e8d8f1c83a27f6b07e88f8a86802a6f3148ef01c6f8ebaa91a|Program Files/Windows Sidebar/Gadgets/Clock.Gadget/images/modern_settings.png
gadgets/Clock.Gadget/images/novelty.png|cc77957c22481bdb09a313261ae58476b8e567c578a643dc9f71808d28589f2b|Program Files/Windows Sidebar/Gadgets/Clock.Gadget/images/novelty.png
gadgets/Clock.Gadget/images/novelty_dot.png|b384c9ca00f15ff275b5a070800d12e6cea9f84b971c2fcd6065724c9105059a|Program Files/Windows Sidebar/Gadgets/Clock.Gadget/images/novelty_dot.png
gadgets/Clock.Gadget/images/novelty_h.png|01ec12afc80db2562a95f065ede0169b809dc76fe2ea9d4f00bde10cba9bb92b|Program Files/Windows Sidebar/Gadgets/Clock.Gadget/images/novelty_h.png
gadgets/Clock.Gadget/images/novelty_m.png|e1052e7226361ce0b80878511be15832ebf8038bb5bcca1e9054508a3ce9ca46|Program Files/Windows Sidebar/Gadgets/Clock.Gadget/images/novelty_m.png
gadgets/Clock.Gadget/images/novelty_s.png|316bcd75ee5816c1f70238ae7bd81f64ec2441ca17e440ce26698ef244f5057a|Program Files/Windows Sidebar/Gadgets/Clock.Gadget/images/novelty_s.png
gadgets/Clock.Gadget/images/novelty_settings.png|785c3987c7a5f21c0b6527bf9b2f8186c5dbb4346beb4fe9e370b7521a7a4c07|Program Files/Windows Sidebar/Gadgets/Clock.Gadget/images/novelty_settings.png
gadgets/Clock.Gadget/images/settings_box_bottom.png|febd5a7a91b5550600e630b55103f760fc0fb89a0fba098abd0388c28e4ab72c|Program Files/Windows Sidebar/Gadgets/Clock.Gadget/images/settings_box_bottom.png
gadgets/Clock.Gadget/images/settings_box_divider_left.png|92d2391214b363fc7785dc02251ca5a1f748b1e765c5009fc95fe00b2ecf7a10|Program Files/Windows Sidebar/Gadgets/Clock.Gadget/images/settings_box_divider_left.png
gadgets/Clock.Gadget/images/settings_box_divider_right.png|6609a11209dd4785c37f500e592938c5273fb7d1d7a08b1fef7cf6bcbe601b19|Program Files/Windows Sidebar/Gadgets/Clock.Gadget/images/settings_box_divider_right.png
gadgets/Clock.Gadget/images/settings_box_left.png|ad0b83a3d4041415926c34b65f6590eff16bf123adbc54d04b6b7a6e17051e55|Program Files/Windows Sidebar/Gadgets/Clock.Gadget/images/settings_box_left.png
gadgets/Clock.Gadget/images/settings_box_right.png|b13182a978a500858d659d46b34bb781b0d8426bd604b9739639f282c77b44ad|Program Files/Windows Sidebar/Gadgets/Clock.Gadget/images/settings_box_right.png
gadgets/Clock.Gadget/images/settings_box_top.png|a1aaaa8215b3a30baa6e3bbf4215e65e759eb6fe14483268ae09811d343553c4|Program Files/Windows Sidebar/Gadgets/Clock.Gadget/images/settings_box_top.png
gadgets/Clock.Gadget/images/settings_corner_bottom_left.png|e2e8088c371b060703144c45ca296a5ba0be80a7cb291ea33b679a9f6fbd7b70|Program Files/Windows Sidebar/Gadgets/Clock.Gadget/images/settings_corner_bottom_left.png
gadgets/Clock.Gadget/images/settings_corner_bottom_right.png|05d8783c7ff25fd89af086b89c06c86927854cef396138b9f7ca614a62066aed|Program Files/Windows Sidebar/Gadgets/Clock.Gadget/images/settings_corner_bottom_right.png
gadgets/Clock.Gadget/images/settings_corner_top_left.png|6c8e78cae685eccde6b78922d45257098b63f60cf429c727c71f5db00af471b5|Program Files/Windows Sidebar/Gadgets/Clock.Gadget/images/settings_corner_top_left.png
gadgets/Clock.Gadget/images/settings_corner_top_right.png|d0cf384bab114850a45c265e3f6cf8fd0988c4c6b41f82de6f69bdb72f99ebc5|Program Files/Windows Sidebar/Gadgets/Clock.Gadget/images/settings_corner_top_right.png
gadgets/Clock.Gadget/images/settings_divider.png|62bf1d3af7d51940186f868f9d7fc7ac85ac5571a3ce520548dc8140c61497c1|Program Files/Windows Sidebar/Gadgets/Clock.Gadget/images/settings_divider.png
gadgets/Clock.Gadget/images/settings_divider_left.png|1ee33fcf5f57eb986e611766d5dd34dc89c80385d8d889a08cd5f0103285fdff|Program Files/Windows Sidebar/Gadgets/Clock.Gadget/images/settings_divider_left.png
gadgets/Clock.Gadget/images/settings_divider_right.png|d716ab64f6fb17df56c74d5df2a1ac29f940d9fa6779630a6036911fa4d5c527|Program Files/Windows Sidebar/Gadgets/Clock.Gadget/images/settings_divider_right.png
gadgets/Clock.Gadget/images/settings_left_disabled.png|3cc66ccfb269b3d7ac7ec744c12f9e97ba3d08868731f94931cff06cea6cc23d|Program Files/Windows Sidebar/Gadgets/Clock.Gadget/images/settings_left_disabled.png
gadgets/Clock.Gadget/images/settings_left_hover.png|410cbe12b613e9ab7937e5d21588a3f9441d8dddf745990ae57493f92a5aac26|Program Files/Windows Sidebar/Gadgets/Clock.Gadget/images/settings_left_hover.png
gadgets/Clock.Gadget/images/settings_left_pressed.png|56e08fab63f41779500a9a6b3e7ffae580dee1a620a400172818d7b1798804d0|Program Files/Windows Sidebar/Gadgets/Clock.Gadget/images/settings_left_pressed.png
gadgets/Clock.Gadget/images/settings_left_rest.png|3f0cef4cf7d5ab2586446bf6ba03f246ef7d4c16db3407e604012ed9215f870c|Program Files/Windows Sidebar/Gadgets/Clock.Gadget/images/settings_left_rest.png
gadgets/Clock.Gadget/images/settings_right_disabled.png|06c8819b2b8f8f7d336e7ab4e9fca038b19b4cf0675fcf7153e34744f321aba7|Program Files/Windows Sidebar/Gadgets/Clock.Gadget/images/settings_right_disabled.png
gadgets/Clock.Gadget/images/settings_right_hover.png|a90ad603c80f5ec3e64e9c6e8cdbc19c6362a5e942a6c9210bf555c740630088|Program Files/Windows Sidebar/Gadgets/Clock.Gadget/images/settings_right_hover.png
gadgets/Clock.Gadget/images/settings_right_pressed.png|d258c7c7c475acb34599c1647b46160b2861bff38f775c76b2e9709bf2a90596|Program Files/Windows Sidebar/Gadgets/Clock.Gadget/images/settings_right_pressed.png
gadgets/Clock.Gadget/images/settings_right_rest.png|afea20af94edb02919e8a57f38104f8fde1350e5655dacc460a8e0eb2173b440|Program Files/Windows Sidebar/Gadgets/Clock.Gadget/images/settings_right_rest.png
gadgets/Clock.Gadget/images/spacer_highlights.png|e05bdb6b04fbfcce4561ef599e491a7675edf0485c9761dda75ff2d1bc222027|Program Files/Windows Sidebar/Gadgets/Clock.Gadget/images/spacer_highlights.png
gadgets/Clock.Gadget/images/square.png|c1fd7a04c1e9237b4ff22240066b7b33819cc5ec661bf0369869acfba8621ff2|Program Files/Windows Sidebar/Gadgets/Clock.Gadget/images/square.png
gadgets/Clock.Gadget/images/square_dot.png|d0d8dd3bb18bf4338958b98d19eaf2c5b7fb9a41c6756df213dbf76d99d2570a|Program Files/Windows Sidebar/Gadgets/Clock.Gadget/images/square_dot.png
gadgets/Clock.Gadget/images/square_h.png|f6984c76dc3d55cc0ffc0eb2845fae79444a3fe87e385bd14c856c1cb970a780|Program Files/Windows Sidebar/Gadgets/Clock.Gadget/images/square_h.png
gadgets/Clock.Gadget/images/square_highlights.png|f77cff5062d31f92e0056ff607dfa3e120262a7698f9cb9d61357306ee2a34b9|Program Files/Windows Sidebar/Gadgets/Clock.Gadget/images/square_highlights.png
gadgets/Clock.Gadget/images/square_m.png|10edc5e9cc161685ce0176c3afe14971bb14940518af65c28d56ae4dddb0665c|Program Files/Windows Sidebar/Gadgets/Clock.Gadget/images/square_m.png
gadgets/Clock.Gadget/images/square_s.png|90f16256cb656082a62f6b14426c4a82d292778374d7adbc274dc68302e04fb4|Program Files/Windows Sidebar/Gadgets/Clock.Gadget/images/square_s.png
gadgets/Clock.Gadget/images/square_settings.png|9b1b47a4884ce698f10afbc9d2a7f2952b945ce0bbfd28d8959b766de282b267|Program Files/Windows Sidebar/Gadgets/Clock.Gadget/images/square_settings.png
gadgets/Clock.Gadget/images/system.png|455664b5208c863b38317f393cc895651d0f69803fbf8f2ca17abf28201fecd5|Program Files/Windows Sidebar/Gadgets/Clock.Gadget/images/system.png
gadgets/Clock.Gadget/images/system_dot.png|a5af4656d7c7904c54efe017adc7136da9c1877aec6d655e5e59af4c15168de9|Program Files/Windows Sidebar/Gadgets/Clock.Gadget/images/system_dot.png
gadgets/Clock.Gadget/images/system_h.png|e660c96141d4189ab50f29d93a61654de7e3d9091749e32b49d5d85cbbc8b4ef|Program Files/Windows Sidebar/Gadgets/Clock.Gadget/images/system_h.png
gadgets/Clock.Gadget/images/system_highlights.png|7f416346db48e479375d122e88c7b4cafa6f2818e3f9dbdffc1671b93b48e443|Program Files/Windows Sidebar/Gadgets/Clock.Gadget/images/system_highlights.png
gadgets/Clock.Gadget/images/system_m.png|6e251fee47f987a75ee81098066127d3d12c492c9807e500399b1ab9e570c1f7|Program Files/Windows Sidebar/Gadgets/Clock.Gadget/images/system_m.png
gadgets/Clock.Gadget/images/system_s.png|eb09a0f4fe7236c82804d18e34fec9177569cfd29231f6df96b4d0038e65dc3d|Program Files/Windows Sidebar/Gadgets/Clock.Gadget/images/system_s.png
gadgets/Clock.Gadget/images/system_settings.png|bc5f38f503f49c5475d749217cd3103c5bd679f5b78aba9ecb0659ee7bbcac5c|Program Files/Windows Sidebar/Gadgets/Clock.Gadget/images/system_settings.png
gadgets/Clock.Gadget/images/trad.png|7e034a1f30c785f266741a66aa0bc8da6e79f2e0931144d414130919ed237334|Program Files/Windows Sidebar/Gadgets/Clock.Gadget/images/trad.png
gadgets/Clock.Gadget/images/trad_dot.png|d4345a0f0b3017b0ef6e5290b2082d4a6047d5e348e8c0ad9ec51eddce7da3e5|Program Files/Windows Sidebar/Gadgets/Clock.Gadget/images/trad_dot.png
gadgets/Clock.Gadget/images/trad_h.png|f522ee7b51fba9c34b7d14239fc666a71f2812422fdc46c7ef15153523d73954|Program Files/Windows Sidebar/Gadgets/Clock.Gadget/images/trad_h.png
gadgets/Clock.Gadget/images/trad_highlights.png|dc93d42333e777fbf9cf89e738c11fd7ed1adce958cb0dc48e97cb5aacc00cd7|Program Files/Windows Sidebar/Gadgets/Clock.Gadget/images/trad_highlights.png
gadgets/Clock.Gadget/images/trad_m.png|11bc15ca945f1b74529595bf92e2cbe0ba7448ce3cd2e0de0765a5e8574d7e5a|Program Files/Windows Sidebar/Gadgets/Clock.Gadget/images/trad_m.png
gadgets/Clock.Gadget/images/trad_s.png|e5489ab293f5edd244e4ee794946908f563d1924ab65f9503c99710f4de4732b|Program Files/Windows Sidebar/Gadgets/Clock.Gadget/images/trad_s.png
gadgets/Clock.Gadget/images/trad_settings.png|026105e9ccfd68e8627d1f0e9f6b2c9ba159d123e9e3729f08e22d96e0a91792|Program Files/Windows Sidebar/Gadgets/Clock.Gadget/images/trad_settings.png
gadgets/Clock.Gadget/logo.png|04ce251b18a31e2425d5358c4bce3f075c9e507699fe509d9f17e9b8ec6d5ea9|Program Files/Windows Sidebar/Gadgets/Clock.Gadget/logo.png
gadgets/SlideShow.Gadget/drag.png|852a9df87d7c68ee797cacf716b848e3822c3aca2097cec4c887bf95a52a495f|Program Files/Windows Sidebar/Gadgets/SlideShow.Gadget/drag.png
gadgets/SlideShow.Gadget/icon.png|6b73ed83f462a2f1162fec6aa836fdb43675a982c491bc065c06e69bedc21058|Program Files/Windows Sidebar/Gadgets/SlideShow.Gadget/icon.png
gadgets/SlideShow.Gadget/images/Garden.jpg|d6d351bdfd2ad6a2ae625553ac106271ed65776db2a4410ca063b1a9b3b416d5|Program Files/Windows Sidebar/Gadgets/SlideShow.Gadget/images/Garden.jpg
gadgets/SlideShow.Gadget/images/blank.png|ba81912be49b62425bbd11089563b3e233cf2ac2dff6e9fe435ba6145dfe2878|Program Files/Windows Sidebar/Gadgets/SlideShow.Gadget/images/blank.png
gadgets/SlideShow.Gadget/images/in_sidebar/bg_sidebar.png|5bf10aa77490db27434d049b24ae05b8667a6431a685c3ea8ee4ba5b6bddd27a|Program Files/Windows Sidebar/Gadgets/SlideShow.Gadget/images/in_sidebar/bg_sidebar.png
gadgets/SlideShow.Gadget/images/in_sidebar/slideshow_glass_frame.png|2e1701d153f28b4f36d4542e17595cb1ecd88ecc8a8ede6cf575062039224bba|Program Files/Windows Sidebar/Gadgets/SlideShow.Gadget/images/in_sidebar/slideshow_glass_frame.png
gadgets/SlideShow.Gadget/images/next_down.png|ba1f5b71c762780411a2a4e1b7fa0269f08ababc7e655af61458875782343e29|Program Files/Windows Sidebar/Gadgets/SlideShow.Gadget/images/next_down.png
gadgets/SlideShow.Gadget/images/next_hov.png|923afff70bc030d4d91b2d3470adf0b5f80a56270e5559088c8491edb3af4a7a|Program Files/Windows Sidebar/Gadgets/SlideShow.Gadget/images/next_hov.png
gadgets/SlideShow.Gadget/images/next_rest.png|c881c9619a63d2081ceac1a243684d9eff920548890a4e99bba190ee32e7cdd9|Program Files/Windows Sidebar/Gadgets/SlideShow.Gadget/images/next_rest.png
gadgets/SlideShow.Gadget/images/on_desktop/slideshow_glass_frame.png|aa8be814a2a4d33c4b9ce6d53e1301d56f1d012266f016409e59db2f15c88f3b|Program Files/Windows Sidebar/Gadgets/SlideShow.Gadget/images/on_desktop/slideshow_glass_frame.png
gadgets/SlideShow.Gadget/images/pause_down.png|6fd20356563d856b75cd46081bc8ee123f56f289466f5f176395f33c281bb555|Program Files/Windows Sidebar/Gadgets/SlideShow.Gadget/images/pause_down.png
gadgets/SlideShow.Gadget/images/pause_hov.png|eaeaf0391b91f27015d87853de6ca10187e081f27cd1f5a9e29ecac3a85e0048|Program Files/Windows Sidebar/Gadgets/SlideShow.Gadget/images/pause_hov.png
gadgets/SlideShow.Gadget/images/pause_rest.png|95cac1bb79fce1db0dd01dbda9eff54fa392796704fdd573f738d9f1ea3566a7|Program Files/Windows Sidebar/Gadgets/SlideShow.Gadget/images/pause_rest.png
gadgets/SlideShow.Gadget/images/play_down.png|28137b2fe29df7a8eee1e599c5c2c0f0625894f924f613d279310ef4591b95b9|Program Files/Windows Sidebar/Gadgets/SlideShow.Gadget/images/play_down.png
gadgets/SlideShow.Gadget/images/play_hov.png|99fc294d218f03104da749b875a0d40b0e4aa0e543c662387a0f3352ab803a57|Program Files/Windows Sidebar/Gadgets/SlideShow.Gadget/images/play_hov.png
gadgets/SlideShow.Gadget/images/play_rest.png|38278eeafdcc4de9f8f56dc5e81dc9975f6bde4e2d2330a4d62350e376ae19a4|Program Files/Windows Sidebar/Gadgets/SlideShow.Gadget/images/play_rest.png
gadgets/SlideShow.Gadget/images/prev_down.png|717958823eadf7906a9360d5d2a225e62bc43c4f2c8dc6972c726a39d69e0c6e|Program Files/Windows Sidebar/Gadgets/SlideShow.Gadget/images/prev_down.png
gadgets/SlideShow.Gadget/images/prev_hov.png|eba91bf4784ac28e9321a8d4ed790b0c462e0602e3d780b73ba36ce39740bb27|Program Files/Windows Sidebar/Gadgets/SlideShow.Gadget/images/prev_hov.png
gadgets/SlideShow.Gadget/images/prev_rest.png|2945a959a547deb58c13c7ad6ee67a83c3563a7b5764fe7451ce1360e4d5bd60|Program Files/Windows Sidebar/Gadgets/SlideShow.Gadget/images/prev_rest.png
gadgets/SlideShow.Gadget/images/reveal_down.png|41c8d3bcf66c6b73befab3610098f1de8d615fa45e50f85476906418ce297000|Program Files/Windows Sidebar/Gadgets/SlideShow.Gadget/images/reveal_down.png
gadgets/SlideShow.Gadget/images/reveal_hov.png|23af594a6318218ead1b48e730ca7d70f39de945f4ed7d18df5ef793bec95a77|Program Files/Windows Sidebar/Gadgets/SlideShow.Gadget/images/reveal_hov.png
gadgets/SlideShow.Gadget/images/reveal_rest.png|4e860562dc21e5cbae253b7fcf9afe8e866d0a1be1a2c3f501ca5dedb1d9c18e|Program Files/Windows Sidebar/Gadgets/SlideShow.Gadget/images/reveal_rest.png
gadgets/SlideShow.Gadget/logo.png|04ce251b18a31e2425d5358c4bce3f075c9e507699fe509d9f17e9b8ec6d5ea9|Program Files/Windows Sidebar/Gadgets/SlideShow.Gadget/logo.png
gadgets/Weather.Gadget/drag.png|746fca26250e1ff6bbe91f0f821cdad552ebfa31ac10f6ca0c54fc4338b6156d|Program Files/Windows Sidebar/Gadgets/Weather.Gadget/drag.png
gadgets/Weather.Gadget/icon.png|5de6c8b3c7d9783cebc632424c56dd879506d337326a87484472d91f2f8eff6b|Program Files/Windows Sidebar/Gadgets/Weather.Gadget/icon.png
gadgets/Weather.Gadget/images/1.png|d4d74fa3f867e41db1e825ee61055a91940cfbfd3e731ab00121317d2dca6c6d|Program Files/Windows Sidebar/Gadgets/Weather.Gadget/images/1.png
gadgets/Weather.Gadget/images/10.png|e5594e0d76c16811ae316ca81684e7e4dd9abfe553396046457b55f11f49f1a3|Program Files/Windows Sidebar/Gadgets/Weather.Gadget/images/10.png
gadgets/Weather.Gadget/images/11.png|e5594e0d76c16811ae316ca81684e7e4dd9abfe553396046457b55f11f49f1a3|Program Files/Windows Sidebar/Gadgets/Weather.Gadget/images/11.png
gadgets/Weather.Gadget/images/12.png|e5594e0d76c16811ae316ca81684e7e4dd9abfe553396046457b55f11f49f1a3|Program Files/Windows Sidebar/Gadgets/Weather.Gadget/images/12.png
gadgets/Weather.Gadget/images/13.png|917b1fb74f73aaa5f9fa0e5905508a2c91cd4e7e825cbf9a3452ab1f0356f9a9|Program Files/Windows Sidebar/Gadgets/Weather.Gadget/images/13.png
gadgets/Weather.Gadget/images/14.png|917b1fb74f73aaa5f9fa0e5905508a2c91cd4e7e825cbf9a3452ab1f0356f9a9|Program Files/Windows Sidebar/Gadgets/Weather.Gadget/images/14.png
gadgets/Weather.Gadget/images/15.png|917b1fb74f73aaa5f9fa0e5905508a2c91cd4e7e825cbf9a3452ab1f0356f9a9|Program Files/Windows Sidebar/Gadgets/Weather.Gadget/images/15.png
gadgets/Weather.Gadget/images/16.png|917b1fb74f73aaa5f9fa0e5905508a2c91cd4e7e825cbf9a3452ab1f0356f9a9|Program Files/Windows Sidebar/Gadgets/Weather.Gadget/images/16.png
gadgets/Weather.Gadget/images/17.png|f564dd2b3feea44a60d83b82ddc1ddccb07f4d39416415e0c5f6f0824cdba109|Program Files/Windows Sidebar/Gadgets/Weather.Gadget/images/17.png
gadgets/Weather.Gadget/images/18.png|f564dd2b3feea44a60d83b82ddc1ddccb07f4d39416415e0c5f6f0824cdba109|Program Files/Windows Sidebar/Gadgets/Weather.Gadget/images/18.png
gadgets/Weather.Gadget/images/19.png|9b580f755411538ad66b74709338ee10085b0772db6bdc3e3ce5b12dc02f4dd9|Program Files/Windows Sidebar/Gadgets/Weather.Gadget/images/19.png
gadgets/Weather.Gadget/images/1px.gif|b1442e85b03bdcaf66dc58c7abb98745dd2687d86350be9a298a1d9382ac849b|Program Files/Windows Sidebar/Gadgets/Weather.Gadget/images/1px.gif
gadgets/Weather.Gadget/images/2.png|d4d74fa3f867e41db1e825ee61055a91940cfbfd3e731ab00121317d2dca6c6d|Program Files/Windows Sidebar/Gadgets/Weather.Gadget/images/2.png
gadgets/Weather.Gadget/images/20.png|9b580f755411538ad66b74709338ee10085b0772db6bdc3e3ce5b12dc02f4dd9|Program Files/Windows Sidebar/Gadgets/Weather.Gadget/images/20.png
gadgets/Weather.Gadget/images/21.png|9b580f755411538ad66b74709338ee10085b0772db6bdc3e3ce5b12dc02f4dd9|Program Files/Windows Sidebar/Gadgets/Weather.Gadget/images/21.png
gadgets/Weather.Gadget/images/22.png|9b580f755411538ad66b74709338ee10085b0772db6bdc3e3ce5b12dc02f4dd9|Program Files/Windows Sidebar/Gadgets/Weather.Gadget/images/22.png
gadgets/Weather.Gadget/images/23.png|2bcde7b0c5175a46fa7d15f7fccb1fbbd234241215c088b8c8185012b9363409|Program Files/Windows Sidebar/Gadgets/Weather.Gadget/images/23.png
gadgets/Weather.Gadget/images/24.png|2bcde7b0c5175a46fa7d15f7fccb1fbbd234241215c088b8c8185012b9363409|Program Files/Windows Sidebar/Gadgets/Weather.Gadget/images/24.png
gadgets/Weather.Gadget/images/25.png|2bcde7b0c5175a46fa7d15f7fccb1fbbd234241215c088b8c8185012b9363409|Program Files/Windows Sidebar/Gadgets/Weather.Gadget/images/25.png
gadgets/Weather.Gadget/images/26.png|66614ae5b00ba396c446b993cc7fccc30e4902ce88bb9158737281eb62e3aad0|Program Files/Windows Sidebar/Gadgets/Weather.Gadget/images/26.png
gadgets/Weather.Gadget/images/27.png|66614ae5b00ba396c446b993cc7fccc30e4902ce88bb9158737281eb62e3aad0|Program Files/Windows Sidebar/Gadgets/Weather.Gadget/images/27.png
gadgets/Weather.Gadget/images/28.png|66614ae5b00ba396c446b993cc7fccc30e4902ce88bb9158737281eb62e3aad0|Program Files/Windows Sidebar/Gadgets/Weather.Gadget/images/28.png
gadgets/Weather.Gadget/images/29.png|1166b22ef77c7940b170a5dc98d77099311068b49379dc66822c6d840e89b5b8|Program Files/Windows Sidebar/Gadgets/Weather.Gadget/images/29.png
gadgets/Weather.Gadget/images/3.png|d4d74fa3f867e41db1e825ee61055a91940cfbfd3e731ab00121317d2dca6c6d|Program Files/Windows Sidebar/Gadgets/Weather.Gadget/images/3.png
gadgets/Weather.Gadget/images/30.png|1166b22ef77c7940b170a5dc98d77099311068b49379dc66822c6d840e89b5b8|Program Files/Windows Sidebar/Gadgets/Weather.Gadget/images/30.png
gadgets/Weather.Gadget/images/31.png|be6774aa4dbe28c2df435f0cf70dd273fd2a600a45cff294bb51666caf889f2e|Program Files/Windows Sidebar/Gadgets/Weather.Gadget/images/31.png
gadgets/Weather.Gadget/images/32.png|be6774aa4dbe28c2df435f0cf70dd273fd2a600a45cff294bb51666caf889f2e|Program Files/Windows Sidebar/Gadgets/Weather.Gadget/images/32.png
gadgets/Weather.Gadget/images/33.png|1166b22ef77c7940b170a5dc98d77099311068b49379dc66822c6d840e89b5b8|Program Files/Windows Sidebar/Gadgets/Weather.Gadget/images/33.png
gadgets/Weather.Gadget/images/34.png|1166b22ef77c7940b170a5dc98d77099311068b49379dc66822c6d840e89b5b8|Program Files/Windows Sidebar/Gadgets/Weather.Gadget/images/34.png
gadgets/Weather.Gadget/images/35.png|e5594e0d76c16811ae316ca81684e7e4dd9abfe553396046457b55f11f49f1a3|Program Files/Windows Sidebar/Gadgets/Weather.Gadget/images/35.png
gadgets/Weather.Gadget/images/36.png|be6774aa4dbe28c2df435f0cf70dd273fd2a600a45cff294bb51666caf889f2e|Program Files/Windows Sidebar/Gadgets/Weather.Gadget/images/36.png
gadgets/Weather.Gadget/images/37.png|d4d74fa3f867e41db1e825ee61055a91940cfbfd3e731ab00121317d2dca6c6d|Program Files/Windows Sidebar/Gadgets/Weather.Gadget/images/37.png
gadgets/Weather.Gadget/images/38.png|d4d74fa3f867e41db1e825ee61055a91940cfbfd3e731ab00121317d2dca6c6d|Program Files/Windows Sidebar/Gadgets/Weather.Gadget/images/38.png
gadgets/Weather.Gadget/images/39.png|e5594e0d76c16811ae316ca81684e7e4dd9abfe553396046457b55f11f49f1a3|Program Files/Windows Sidebar/Gadgets/Weather.Gadget/images/39.png
gadgets/Weather.Gadget/images/4.png|d4d74fa3f867e41db1e825ee61055a91940cfbfd3e731ab00121317d2dca6c6d|Program Files/Windows Sidebar/Gadgets/Weather.Gadget/images/4.png
gadgets/Weather.Gadget/images/40.png|a03d5a9bfa5cf5c614abd7ad1c64cb1caa2b1eb46303f89f74c278be1f11cb28|Program Files/Windows Sidebar/Gadgets/Weather.Gadget/images/40.png
gadgets/Weather.Gadget/images/41.png|917b1fb74f73aaa5f9fa0e5905508a2c91cd4e7e825cbf9a3452ab1f0356f9a9|Program Files/Windows Sidebar/Gadgets/Weather.Gadget/images/41.png
gadgets/Weather.Gadget/images/42.png|8bacce259a2acb3d9e7556a1a432009734549674858604ad5e89f10170d5367d|Program Files/Windows Sidebar/Gadgets/Weather.Gadget/images/42.png
gadgets/Weather.Gadget/images/43.png|8bacce259a2acb3d9e7556a1a432009734549674858604ad5e89f10170d5367d|Program Files/Windows Sidebar/Gadgets/Weather.Gadget/images/43.png
gadgets/Weather.Gadget/images/44.png|5c510c7c6d86aa7b8f09f265d96afbe14beb034c6fb74509e9593b2d4862b290|Program Files/Windows Sidebar/Gadgets/Weather.Gadget/images/44.png
gadgets/Weather.Gadget/images/45.png|e5594e0d76c16811ae316ca81684e7e4dd9abfe553396046457b55f11f49f1a3|Program Files/Windows Sidebar/Gadgets/Weather.Gadget/images/45.png
gadgets/Weather.Gadget/images/46.png|917b1fb74f73aaa5f9fa0e5905508a2c91cd4e7e825cbf9a3452ab1f0356f9a9|Program Files/Windows Sidebar/Gadgets/Weather.Gadget/images/46.png
gadgets/Weather.Gadget/images/47.png|d4d74fa3f867e41db1e825ee61055a91940cfbfd3e731ab00121317d2dca6c6d|Program Files/Windows Sidebar/Gadgets/Weather.Gadget/images/47.png
gadgets/Weather.Gadget/images/5.png|86968256c8b714d69861984d9dcdd896c47b80e00d2607bedf3ca425f895f7ab|Program Files/Windows Sidebar/Gadgets/Weather.Gadget/images/5.png
gadgets/Weather.Gadget/images/6.png|86968256c8b714d69861984d9dcdd896c47b80e00d2607bedf3ca425f895f7ab|Program Files/Windows Sidebar/Gadgets/Weather.Gadget/images/6.png
gadgets/Weather.Gadget/images/7.png|86968256c8b714d69861984d9dcdd896c47b80e00d2607bedf3ca425f895f7ab|Program Files/Windows Sidebar/Gadgets/Weather.Gadget/images/7.png
gadgets/Weather.Gadget/images/8.png|e5594e0d76c16811ae316ca81684e7e4dd9abfe553396046457b55f11f49f1a3|Program Files/Windows Sidebar/Gadgets/Weather.Gadget/images/8.png
gadgets/Weather.Gadget/images/9.png|e5594e0d76c16811ae316ca81684e7e4dd9abfe553396046457b55f11f49f1a3|Program Files/Windows Sidebar/Gadgets/Weather.Gadget/images/9.png
gadgets/Weather.Gadget/images/BLACK-base.png|32b7d109001d9d61a7dfd5298012670f7fbe3f42e6fee5e6d34c1d107befd8be|Program Files/Windows Sidebar/Gadgets/Weather.Gadget/images/BLACK-base.png
gadgets/Weather.Gadget/images/BLACK-highlight-01.png|df8067d1126774aa4904ca2a43486cc2b641d938533ebea94334590c9e55a62b|Program Files/Windows Sidebar/Gadgets/Weather.Gadget/images/BLACK-highlight-01.png
gadgets/Weather.Gadget/images/BLACK-highlight-02.png|6cfbc94f41ce52ec3784ae0580b38d03b8ae74736a89025ac5e140ebaa8d11d5|Program Files/Windows Sidebar/Gadgets/Weather.Gadget/images/BLACK-highlight-02.png
gadgets/Weather.Gadget/images/BLACKDOCKED-base.png|6286cb2037dc412358e589ce682cc0d0f442d57dd6ac25b807fd9fd2321ee94b|Program Files/Windows Sidebar/Gadgets/Weather.Gadget/images/BLACKDOCKED-base.png
gadgets/Weather.Gadget/images/BLACKDOCKED-highlight-01.png|ac5bfdade3bda47f53f25b6c22765a5abfb5316c879f67d9b52fbe34d8f4485a|Program Files/Windows Sidebar/Gadgets/Weather.Gadget/images/BLACKDOCKED-highlight-01.png
gadgets/Weather.Gadget/images/BLACKDOCKED-highlight-02.png|02f074663154c23ad22d42eae371217586c7a337aa85122f85680bf16cd46d1b|Program Files/Windows Sidebar/Gadgets/Weather.Gadget/images/BLACKDOCKED-highlight-02.png
gadgets/Weather.Gadget/images/BLUE-base.png|7bf939f8e3ccc060d24a1a497907813bd39c33686d767f338e1f56958efdd3fe|Program Files/Windows Sidebar/Gadgets/Weather.Gadget/images/BLUE-base.png
gadgets/Weather.Gadget/images/BLUE-highlight-01.png|6b41e416670d83bd17d7204152f0d33fb3826bc4a9464c54f5e8c6524bc20e8c|Program Files/Windows Sidebar/Gadgets/Weather.Gadget/images/BLUE-highlight-01.png
gadgets/Weather.Gadget/images/BLUE-highlight-02.png|6cfbc94f41ce52ec3784ae0580b38d03b8ae74736a89025ac5e140ebaa8d11d5|Program Files/Windows Sidebar/Gadgets/Weather.Gadget/images/BLUE-highlight-02.png
gadgets/Weather.Gadget/images/BLUEDOCKED-base.png|f7bf1932538706247ddc3c89674553237fc1863cfda0b0e049245b750ca7e3b0|Program Files/Windows Sidebar/Gadgets/Weather.Gadget/images/BLUEDOCKED-base.png
gadgets/Weather.Gadget/images/BLUEDOCKED-highlight-01.png|3d333628f5d8cda25ab56b373cbc33af39676e9291aa4a3ca2f43850b8b8df69|Program Files/Windows Sidebar/Gadgets/Weather.Gadget/images/BLUEDOCKED-highlight-01.png
gadgets/Weather.Gadget/images/BLUEDOCKED-highlight-02.png|9078c5a155070b848c0370cf5334bee71a5afdf7cb62dfd7ff437c29b28a5a30|Program Files/Windows Sidebar/Gadgets/Weather.Gadget/images/BLUEDOCKED-highlight-02.png
gadgets/Weather.Gadget/images/GRAY-base.png|9dc96d07f5f67db0a97c0ae94778c37eb3cc65bd5c02dc5fa4561735fdec6713|Program Files/Windows Sidebar/Gadgets/Weather.Gadget/images/GRAY-base.png
gadgets/Weather.Gadget/images/GRAY-highlight-01.png|388a68ee34bc27ba6f24203ffbfa93f86efec483fa98b6f26e6c800688ce5450|Program Files/Windows Sidebar/Gadgets/Weather.Gadget/images/GRAY-highlight-01.png
gadgets/Weather.Gadget/images/GRAY-highlight-02.png|6cfbc94f41ce52ec3784ae0580b38d03b8ae74736a89025ac5e140ebaa8d11d5|Program Files/Windows Sidebar/Gadgets/Weather.Gadget/images/GRAY-highlight-02.png
gadgets/Weather.Gadget/images/GRAYDOCKED-base.png|931316b6e2538121e66422d40f4d1cd32b3c35fddfd03e8bf8449a211632d172|Program Files/Windows Sidebar/Gadgets/Weather.Gadget/images/GRAYDOCKED-base.png
gadgets/Weather.Gadget/images/GRAYDOCKED-highlight-01.png|60ada5b1e397fd292a50d4264a1570a5c96abe323024d06d2fd4b6c698938fdf|Program Files/Windows Sidebar/Gadgets/Weather.Gadget/images/GRAYDOCKED-highlight-01.png
gadgets/Weather.Gadget/images/GRAYDOCKED-highlight-02.png|02f074663154c23ad22d42eae371217586c7a337aa85122f85680bf16cd46d1b|Program Files/Windows Sidebar/Gadgets/Weather.Gadget/images/GRAYDOCKED-highlight-02.png
gadgets/Weather.Gadget/images/activity16v.png|06c2c37091f75e2ea22b12595e72b7bbeb6e8d01b691d16c2421c7f4524c45b0|Program Files/Windows Sidebar/Gadgets/Weather.Gadget/images/activity16v.png
gadgets/Weather.Gadget/images/btn_close_down.png|a8173463997aa9eb8db376d3ca210868b7403fd072dce52a3b42772becae67be|Program Files/Windows Sidebar/Gadgets/Weather.Gadget/images/btn_close_down.png
gadgets/Weather.Gadget/images/btn_close_down_BIDI.png|ddeb83b820041079f9b90263e1ff36c4001d96c663dc43b469a583318576ed66|Program Files/Windows Sidebar/Gadgets/Weather.Gadget/images/btn_close_down_BIDI.png
gadgets/Weather.Gadget/images/btn_close_over.png|2681348839429709c25cc8e37a3b654c57c659186c25c8d89c8f740f953b74a3|Program Files/Windows Sidebar/Gadgets/Weather.Gadget/images/btn_close_over.png
gadgets/Weather.Gadget/images/btn_close_up.png|5c99aadd31bca9a757c775f72101d552e614dc1c7dde1ec81fa36c53a8ba9f4a|Program Files/Windows Sidebar/Gadgets/Weather.Gadget/images/btn_close_up.png
gadgets/Weather.Gadget/images/btn_search_down.png|507144699b8d15c7cc358fa7d76d8be6d56138c2259e2a07d39696fefd8d4a61|Program Files/Windows Sidebar/Gadgets/Weather.Gadget/images/btn_search_down.png
gadgets/Weather.Gadget/images/btn_search_down_BIDI.png|174dbcf0649b67d7cc058d2f2d3ac778b82e6b8c24078a85f6ab7f68b7581d17|Program Files/Windows Sidebar/Gadgets/Weather.Gadget/images/btn_search_down_BIDI.png
gadgets/Weather.Gadget/images/btn_search_over.png|672a5364352e5f86e4a272cfb3be1c40d57b43574ec8c838799e2b529927f679|Program Files/Windows Sidebar/Gadgets/Weather.Gadget/images/btn_search_over.png
gadgets/Weather.Gadget/images/btn_search_over_BIDI.png|04f396f2f59c8f37ada15002119481af3f4a66ff05cc88f622d6799bfe10e538|Program Files/Windows Sidebar/Gadgets/Weather.Gadget/images/btn_search_over_BIDI.png
gadgets/Weather.Gadget/images/btn_search_up.png|fb5729c64a75a0640a9c974d85671ac57f3e77ddaecc7dc047ec2f4dbc7fd8ae|Program Files/Windows Sidebar/Gadgets/Weather.Gadget/images/btn_search_up.png
gadgets/Weather.Gadget/images/btn_search_up_BIDI.png|b5237b776ccbbe2447c3ef058dbdb923855d134b3614368d400ec931b86f0a4a|Program Files/Windows Sidebar/Gadgets/Weather.Gadget/images/btn_search_up_BIDI.png
gadgets/Weather.Gadget/images/divider-horizontal.png|b7ca3a37e6e3f49160287133c9ef58db3a0f59c5d9e65cb68f5c9c34fee1ef54|Program Files/Windows Sidebar/Gadgets/Weather.Gadget/images/divider-horizontal.png
gadgets/Weather.Gadget/images/divider-vertical.png|e7a47f85d911f6bdeeaeed490a83dc40a5f4375ec2db333e6e337c439d7721cb|Program Files/Windows Sidebar/Gadgets/Weather.Gadget/images/divider-vertical.png
gadgets/Weather.Gadget/images/docked-loading.png|62b6a37516865cb0b115a4b429ccc7c63cc97c4c57f6e745750749570b28033d|Program Files/Windows Sidebar/Gadgets/Weather.Gadget/images/docked-loading.png
gadgets/Weather.Gadget/images/docked_cloudy.png|54a2f62743280f1140c59e20ed7380e4d956041023e04e717160675463d82956|Program Files/Windows Sidebar/Gadgets/Weather.Gadget/images/docked_cloudy.png
gadgets/Weather.Gadget/images/docked_few-showers.png|4f1bfe7e85c7e1899b2c66cb7ef50c4a380a79ddf6ceff8543550e5f6766b0e8|Program Files/Windows Sidebar/Gadgets/Weather.Gadget/images/docked_few-showers.png
gadgets/Weather.Gadget/images/docked_foggy.png|0cf45d719a8f8688968d5e7ffa3d13e838cbfb865738961aaac338bf3482c94c|Program Files/Windows Sidebar/Gadgets/Weather.Gadget/images/docked_foggy.png
gadgets/Weather.Gadget/images/docked_hail.png|7094f77080d9fd4c6767550cddef3ad21cc927f589be46a940ae8b3fb9cfcf48|Program Files/Windows Sidebar/Gadgets/Weather.Gadget/images/docked_hail.png
gadgets/Weather.Gadget/images/docked_moon-first-quarter.png|547f1766fc2bd130b2636b11fc5ac43b326bf448e44c2d16eabc419b67f934c5|Program Files/Windows Sidebar/Gadgets/Weather.Gadget/images/docked_moon-first-quarter.png
gadgets/Weather.Gadget/images/docked_moon-full.png|2dde05788afd9bef6cd65f80f0b333923535f505e0bb50e6662eab524305c47f|Program Files/Windows Sidebar/Gadgets/Weather.Gadget/images/docked_moon-full.png
gadgets/Weather.Gadget/images/docked_moon-last-quarter.png|99a81a2c80c669fd34c0f10120cacdfb20aaa6f978a5dcf13c2a4bb76e85f256|Program Files/Windows Sidebar/Gadgets/Weather.Gadget/images/docked_moon-last-quarter.png
gadgets/Weather.Gadget/images/docked_moon-new.png|d456922168eec8a01c5c26ce4492766b87a6f0aea5496f2dc465f364b5f4e300|Program Files/Windows Sidebar/Gadgets/Weather.Gadget/images/docked_moon-new.png
gadgets/Weather.Gadget/images/docked_moon-waning-crescent.png|860586408fba71d8dbab87fa0bf4edf9e9e9a5c88d0ec0e7dff6325b6dee4556|Program Files/Windows Sidebar/Gadgets/Weather.Gadget/images/docked_moon-waning-crescent.png
gadgets/Weather.Gadget/images/docked_moon-waning-gibbous.png|9b9f8a00ee73fe1dab27a1421d05e5e9aa0081381abfeb4b2c6bba35c7ae1eb3|Program Files/Windows Sidebar/Gadgets/Weather.Gadget/images/docked_moon-waning-gibbous.png
gadgets/Weather.Gadget/images/docked_moon-waxing-crescent.png|58d874c7f141d73bee50e1b495a04954ae2f7a1ff952120ab7713ceaaa42a61d|Program Files/Windows Sidebar/Gadgets/Weather.Gadget/images/docked_moon-waxing-crescent.png
gadgets/Weather.Gadget/images/docked_moon-waxing-gibbous.png|735ac6ec7cba59973f95c5d0fb2e5e74179093346f986268f79c96cf7ec65dbc|Program Files/Windows Sidebar/Gadgets/Weather.Gadget/images/docked_moon-waxing-gibbous.png
gadgets/Weather.Gadget/images/docked_partly-cloudy.png|e02dd3abff5f5e476279050a0aade6a2dd61a545642a56232f64f20f374f761e|Program Files/Windows Sidebar/Gadgets/Weather.Gadget/images/docked_partly-cloudy.png
gadgets/Weather.Gadget/images/docked_rainy.png|56e6e438628db32357f098b3b6071dd4267c31802419bdedf5f664cdb1de0105|Program Files/Windows Sidebar/Gadgets/Weather.Gadget/images/docked_rainy.png
gadgets/Weather.Gadget/images/docked_snow.png|b649552ed299c535d8703825e5f1adcbe56de4265b2eebfbd0046e98f894b3ab|Program Files/Windows Sidebar/Gadgets/Weather.Gadget/images/docked_snow.png
gadgets/Weather.Gadget/images/docked_sun.png|0808d57b1ade4b7a7f73eca15ea88c983b5ea656d611d170f4ab5ac452edacd6|Program Files/Windows Sidebar/Gadgets/Weather.Gadget/images/docked_sun.png
gadgets/Weather.Gadget/images/docked_thunderstorm.png|5ea71db29ae8b96cdc6c7d935ddb0097f35bc567338dc5f22fe9c6b0d3497d9c|Program Files/Windows Sidebar/Gadgets/Weather.Gadget/images/docked_thunderstorm.png
gadgets/Weather.Gadget/images/docked_windy.png|855bb54c424f021dc1e2216eedd16c7c15a5d2de77abeeadf320717638cbcec4|Program Files/Windows Sidebar/Gadgets/Weather.Gadget/images/docked_windy.png
gadgets/Weather.Gadget/images/info.png|2ab28364860b34593bb53c75de94014940f1279d6037986dc65b6cf5760b8ef1|Program Files/Windows Sidebar/Gadgets/Weather.Gadget/images/info.png
gadgets/Weather.Gadget/images/search_background.png|b7b24c2d115d40890af0c85e3bc345c6d885bb7733f72d389b56b042f91432fa|Program Files/Windows Sidebar/Gadgets/Weather.Gadget/images/search_background.png
gadgets/Weather.Gadget/images/undocked-loading.png|56d62edd00231135acdec72deeaffd041f0e12b0236e32b9a39d6c94858e974f|Program Files/Windows Sidebar/Gadgets/Weather.Gadget/images/undocked-loading.png
gadgets/Weather.Gadget/images/undocked_cloudy.png|ad54502b8e547a43f22664e9dea8e3d906399ff2063f54194ba49d91161095d2|Program Files/Windows Sidebar/Gadgets/Weather.Gadget/images/undocked_cloudy.png
gadgets/Weather.Gadget/images/undocked_few-showers.png|f0d21207c8d05635d2bbe6d8005b0bc8d4028d3503a3a776f91bae25954fe49c|Program Files/Windows Sidebar/Gadgets/Weather.Gadget/images/undocked_few-showers.png
gadgets/Weather.Gadget/images/undocked_foggy.png|7ea698074794eca58950567df0ac1e9dda572113c470a4e336f85754b8a86adc|Program Files/Windows Sidebar/Gadgets/Weather.Gadget/images/undocked_foggy.png
gadgets/Weather.Gadget/images/undocked_hail.png|9743201db44a21606ceca93771b0bfb46e692885aea295c02f437d840f24e6d3|Program Files/Windows Sidebar/Gadgets/Weather.Gadget/images/undocked_hail.png
gadgets/Weather.Gadget/images/undocked_moon-first-quarter.png|22cd68fcbe6630fb4ee6ae21926ebea9cfef075ccd97cf3d0ce0df64b21ed652|Program Files/Windows Sidebar/Gadgets/Weather.Gadget/images/undocked_moon-first-quarter.png
gadgets/Weather.Gadget/images/undocked_moon-full.png|0c043e2b888b2367d46d5cc0e4a5ddcf6f00224faf6f0c51146e874c82847728|Program Files/Windows Sidebar/Gadgets/Weather.Gadget/images/undocked_moon-full.png
gadgets/Weather.Gadget/images/undocked_moon-last-quarter.png|5788d9b2a4f8685e7159264292bcc5139367ded9a05e0f4aaa5ac5ee2c895e68|Program Files/Windows Sidebar/Gadgets/Weather.Gadget/images/undocked_moon-last-quarter.png
gadgets/Weather.Gadget/images/undocked_moon-new.png|b6944ce21dcaeb9d53143a4438f11af9d3bea72f8b022ca4979e629985dbd7c3|Program Files/Windows Sidebar/Gadgets/Weather.Gadget/images/undocked_moon-new.png
gadgets/Weather.Gadget/images/undocked_moon-waning-crescent.png|e2cdd1984d13f099544db8e7ea6894b1e50429ddcd179ed4ecc69f7eaf140f93|Program Files/Windows Sidebar/Gadgets/Weather.Gadget/images/undocked_moon-waning-crescent.png
gadgets/Weather.Gadget/images/undocked_moon-waning-gibbous.png|7b04935f7c75e24d169b44ff0f6be8dcf3ec539103305301b256d3d4978928ea|Program Files/Windows Sidebar/Gadgets/Weather.Gadget/images/undocked_moon-waning-gibbous.png
gadgets/Weather.Gadget/images/undocked_moon-waxing-crescent.png|cfd087756d019c5e14d1bf2ad7e6889cd2f0f97edb870cd2d99fe3cd1bfab5dd|Program Files/Windows Sidebar/Gadgets/Weather.Gadget/images/undocked_moon-waxing-crescent.png
gadgets/Weather.Gadget/images/undocked_moon-waxing-full.png|0c043e2b888b2367d46d5cc0e4a5ddcf6f00224faf6f0c51146e874c82847728|Program Files/Windows Sidebar/Gadgets/Weather.Gadget/images/undocked_moon-waxing-full.png
gadgets/Weather.Gadget/images/undocked_moon-waxing-gibbous.png|757b088be999a8e5d3ffb253445280840a2bef28e021446fdd0a47bfe7b15892|Program Files/Windows Sidebar/Gadgets/Weather.Gadget/images/undocked_moon-waxing-gibbous.png
gadgets/Weather.Gadget/images/undocked_partly-cloudy.png|731e747debf688860cefb2b9684100767c814226893454af8dd8be911436aceb|Program Files/Windows Sidebar/Gadgets/Weather.Gadget/images/undocked_partly-cloudy.png
gadgets/Weather.Gadget/images/undocked_rainy.png|c2dab20c7ef537c7d014888a7a82f13169fc0e8452dac42aaad5d6514d312408|Program Files/Windows Sidebar/Gadgets/Weather.Gadget/images/undocked_rainy.png
gadgets/Weather.Gadget/images/undocked_snow.png|2ebbf556ad95fc222e9d689bc66c531225aacfa4ff56e86306a1c11cab17b8fb|Program Files/Windows Sidebar/Gadgets/Weather.Gadget/images/undocked_snow.png
gadgets/Weather.Gadget/images/undocked_sun.png|ff91ff036c0fad361e5addb71a5006ced472e18d8db80120c6777ef01af8044c|Program Files/Windows Sidebar/Gadgets/Weather.Gadget/images/undocked_sun.png
gadgets/Weather.Gadget/images/undocked_thunderstorm.png|36fab22a094768526cd6b64a89bdfb021b57804b5fb48efea6cd30ab41a28ac8|Program Files/Windows Sidebar/Gadgets/Weather.Gadget/images/undocked_thunderstorm.png
gadgets/Weather.Gadget/images/undocked_windy.png|50ec9bd65c10ff66abb0951f00c56da9d0f96af9137ecfe2f2b7f7b8455ac853|Program Files/Windows Sidebar/Gadgets/Weather.Gadget/images/undocked_windy.png
gadgets/Weather.Gadget/logo.png|07815a1636ce60f71a57f6bde076f3d5cff916e116aaae6660e2a5eaab1289a4|Program Files/Windows Sidebar/Gadgets/Weather.Gadget/logo.png
sounds/balloon.wav|1e646954174841eb594f8573dc761276d3132b2389554709ad7d44e6772d7a7d|Windows/Media/Windows Balloon.wav
sounds/battery-critical.wav|873f59c7c115bdbefd4e3f650160a72e4aea2f9af486ec95d6dd2c0be430cf79|Windows/Media/Windows Battery Critical.wav
sounds/battery-low.wav|61eb4fbc96d79324053dcce4a70dc2d403e61259ae6bd959fa9e47008147d186|Windows/Media/Windows Battery Low.wav
sounds/critical-stop.wav|27dc9782ffaa29c830158374afb9370f4df32d03b592e83251b55e0a8e972b98|Windows/Media/Windows Critical Stop.wav
sounds/ding.wav|7020a1c64207ad8e60062d5400e1332bd07d95bb59cc82af2dd4b39347c64a76|Windows/Media/Windows Ding.wav
sounds/error.wav|217e7bbcba8b6f5af6b4ceb03f11b5d8393862b7aae56db6278911968a48c8b2|Windows/Media/Windows Error.wav
sounds/exclamation.wav|ecaea6f9d11635b19e332fce70807d5c8370c546c03c17ae613ff0de1dd2465c|Windows/Media/Windows Exclamation.wav
sounds/hardware-fail.wav|0c4f60760d9b80f3f053832d6ae1fcb90576cb118a3e0a1574e234eaf7cbf4ee|Windows/Media/Windows Hardware Fail.wav
sounds/hardware-insert.wav|2536d34c366b343cc07b53850ae800fadc608149fe4d04357fefa80b447a1c1e|Windows/Media/Windows Hardware Insert.wav
sounds/hardware-remove.wav|fe1ad6c8b2fdbb60b7c3b5f5303165f713745f05aaf85e0bd358eb3b81700e98|Windows/Media/Windows Hardware Remove.wav
sounds/logoff.wav|1e52df819839e301a2145a373440153422fef3a1ec2bae7e1268c9aba8d32803|Windows/Media/Windows Logoff Sound.wav
sounds/logon.wav|2188c09d0cf64b7eb870c67ce3dd09167589e9d286f488742b2342571d0f8a99|Windows/Media/Windows Logon Sound.wav
sounds/minimize.wav|3b71ca5a67432991ffa159d082cbf96c7948ad2db7486e6d491063d68863e3c2|Windows/Media/Windows Minimize.wav
sounds/navigation-start.wav|682c8a7cf410de17c249775aee568ec1f9e3341bd4409e96ccbba4882f1d8670|Windows/Media/Windows Navigation Start.wav
sounds/notify.wav|e134873ca4fd9140e5a90ed5d57814115b2f283dacde68de138b25a5c80ec264|Windows/Media/Windows Notify.wav
sounds/recycle.wav|f1eb9d205799a5b803b1df4de4e8feb54acd1a9ac9f3732b1a17a0cff02d71a7|Windows/Media/Windows Recycle.wav
sounds/restore.wav|e201003b7edd20e3e8de9921e358668a5fd84bc650bcd7ded06fad5f3bff0a49|Windows/Media/Windows Restore.wav
sounds/shutdown.wav|a17d556b4744e1578f8e110f60e3c32c44ccdf99107c67cc5fda7da68cf210db|Windows/Media/Windows Shutdown.wav
sounds/uac.wav|cf6c22452ff7e392cfdfb09a2736c40bc0ef47dc8285df2401d7a4c84d084804|Windows/Media/Windows User Account Control.wav
wallpapers/img1.jpg|5bc783ab329d941ecff5d9248cb1702021de460f61ac97afde5b029c21d08773|Windows/Web/Wallpaper/img1.jpg
wallpapers/img10.jpg|ac44d94d861859a3e6415e029c24512294db3302e31fb0a3982834731e453184|Windows/Web/Wallpaper/img10.jpg
wallpapers/img11.jpg|922e44a9f7cbe705ba3a82affa3a5b05ce4a6a064181c7435d9fc2cb9ebc3eb6|Windows/Web/Wallpaper/img11.jpg
wallpapers/img12.jpg|e16ff81339d936d8bca5b8a75ab2af9146f5fe4752cb00ccd8c89b27d1315476|Windows/Web/Wallpaper/img12.jpg
wallpapers/img13.jpg|3695eaa0f76d6988f139c7f0c579048b9a7b9cede3bb282460615d016930ae4b|Windows/Web/Wallpaper/img13.jpg
wallpapers/img14.jpg|816e5b792ea44e9e9ea304db4610b2af43f8674cdcb8b48c515c9e480a574965|Windows/Web/Wallpaper/img14.jpg
wallpapers/img15.jpg|241b322dfea142ce14c53d7c17eb7084470b0436bbb417f3aee9a129dc948a5f|Windows/Web/Wallpaper/img15.jpg
wallpapers/img16.jpg|a383425b5ab320500e4dc23df1c7c425b535704971caf3bb2af6d371881b2c53|Windows/Web/Wallpaper/img16.jpg
wallpapers/img17.jpg|7543f627ccd900ab6141303bf1b434f68919eb6885759c3fd022544e90eda45f|Windows/Web/Wallpaper/img17.jpg
wallpapers/img18.jpg|959c063e309ccc3a737061fc59603eba705ea54861ef4a55ca098242bfaea9b1|Windows/Web/Wallpaper/img18.jpg
wallpapers/img19.jpg|5e8cff9a0c582d4af95eac7664c3d6edfee722641672c34b186c8e1a2d0dda02|Windows/Web/Wallpaper/img19.jpg
wallpapers/img2.jpg|cad26aac127c7cefcacbab71a4927106c9d902b83a046668cce8bd3959bef9a1|Windows/Web/Wallpaper/img2.jpg
wallpapers/img20.jpg|ac99b1ce7d2b749e21160748c996b337ebe155384400f0fc7e2afdb0f9c6cd48|Windows/Web/Wallpaper/img20.jpg
wallpapers/img21.jpg|da6452b01856f18f9b9f2e983953bdc5ae0c824a9da0f4776d5c78bff0d3bfc5|Windows/Web/Wallpaper/img21.jpg
wallpapers/img22.jpg|292e326feccbb47bc2fc41a22edf28ea02257bf05871d28ebab893cabe66232a|Windows/Web/Wallpaper/img22.jpg
wallpapers/img23.jpg|e4224a98ddb572d21a4f0790be3a2e4986d56499b72c253bab8435dfec2d3c01|Windows/Web/Wallpaper/img23.jpg
wallpapers/img24.jpg|2dddd4a16d315f061e60a5859f982429898096bd173f4cbaaa3a8d47ccae2f8f|Windows/Web/Wallpaper/img24.jpg
wallpapers/img25.jpg|1962a3572f2341fa0f81ae001a8b337e93f1c8244a4b8e9c884f830c43f29e7d|Windows/Web/Wallpaper/img25.jpg
wallpapers/img26.jpg|9520ee2069d4d494e048888e1361015955015f25ac06d460d0813bbdbfb6150e|Windows/Web/Wallpaper/img26.jpg
wallpapers/img27.jpg|59fee70364246a30860263f4e70168d598a308567a77a9270c4f6d11201972df|Windows/Web/Wallpaper/img27.jpg
wallpapers/img28.jpg|f28542274945458a2d074583a2810eead70256eb511d841abb0d5bb0f8fd3cd9|Windows/Web/Wallpaper/img28.jpg
wallpapers/img29.jpg|a9a6124975fa78ab3146aa9b346827094e3d294b73f383de89648239b6d2984b|Windows/Web/Wallpaper/img29.jpg
wallpapers/img3.jpg|2a3e95366ef03705825e584c9bb26a09cbfe7be742ac9170a0de0232d3a92def|Windows/Web/Wallpaper/img3.jpg
wallpapers/img30.jpg|394290dbc6a3a291b0cf6af4817c6300039aa6da3d741c9590d752c5fef43a0c|Windows/Web/Wallpaper/img30.jpg
wallpapers/img31.jpg|d42e15155af121aec4463a0138bfea4bd959d0e02acfc9065dd3a2932b3230fb|Windows/Web/Wallpaper/img31.jpg
wallpapers/img32.jpg|6984a4fb96317c7d6aefd4a849327ca93b48f066d8be8c8f1fe3deac87a966bc|Windows/Web/Wallpaper/img32.jpg
wallpapers/img33.jpg|a67bbf0837bbeb54d7b82218d5d76971164436959106c70e3d6d4f7fc2e7361c|Windows/Web/Wallpaper/img33.jpg
wallpapers/img34.jpg|d6681df65075a1a807ff44b34aab35b53e335d6f71c7771bdddbac530dfa9c45|Windows/Web/Wallpaper/img34.jpg
wallpapers/img35.jpg|df2e4447bdf632ea990153dca049d8515eb6575b07433f90f29c533f732d4ec6|Windows/Web/Wallpaper/img35.jpg
wallpapers/img36.jpg|77fd927332fcec551233871031755589aa1796c9ca424cf3f31b1d155cd61285|Windows/Web/Wallpaper/img36.jpg
wallpapers/img4.jpg|3f5fbeb429be3eb00caeaf189a5705e92887fa16ce702bfe1bde7c355e97fc3c|Windows/Web/Wallpaper/img4.jpg
wallpapers/img5.jpg|40a84908b3c957bd5ac2ab5d8655bfd3938c2ac38c162d1fb54a8032b451201f|Windows/Web/Wallpaper/img5.jpg
wallpapers/img6.jpg|d9a2744a8fc7f7bcb4e27194a89c083831f53edc2ec5b29995b4ac0366522fc8|Windows/Web/Wallpaper/img6.jpg
wallpapers/img7.jpg|217b8fb16b0a9f1974dabd746cf915d04000594f595e501c229af941b8674396|Windows/Web/Wallpaper/img7.jpg
wallpapers/img8.jpg|cf1aad77d7ba34fe6e2fac47ab8803d292668f3e00d365e710a86fc74d77d025|Windows/Web/Wallpaper/img8.jpg
wallpapers/img9.jpg|ade9802bddcbf2082f40f0a871f853740377d0ff428d5481e2b44e211ed350b9|Windows/Web/Wallpaper/img9.jpg
EOF
)

# ── Derived: dest | sha256 (tree hash for dirs) | method | input | member ───
#   msstyles  vistatool msstyles: props.json, parts.txt, image/, stream/, parts/
#   wave      WAVE resource <member> of <input>
#   peres     PE resources of <input>, types <member>
#   icons     GROUP_ICON of <input> as one-image .ico files, sizes <member>
#   xcursor   the Aero pointers (<input> = cursors dir) + user32's text/cross
#   gtk       the B00merang tarball, unpacked; member = its top directory
DERIVED=$(cat <<'EOF'
graphics/aero|eb9835d548af978332c028688e4e27994970ad85b059c14b59dd79bafd2753e5|msstyles|binaries/aero.msstyles|-
sounds/startup.wav|1d31bad8d79ff31b7917c7290c8b96aa5f3b45a984313247b23c6996c7a29ade|wave|binaries/imageres.dll|5051
graphics/explorer|021f82bf63d88568e193b00c9e76ece91cbdae264e0a847dc14800a2730813bc|peres|binaries/explorer.exe|BITMAP,PNGFILE
graphics/authui|d5c9ce62ee50101f0461b1869e22dc63b47ca2220d2462e06c6ea4a59e8af91f|peres|binaries/authui.dll|BITMAP,IMAGE,UIFILE
graphics/authui-strings|0e7ca592b1f26687ec038e3da02781730602fd99d14ed2a7c20f3f6bb9776197|peres|binaries/authui.dll.mui|STRING,DIALOG
graphics/consent-strings|9a76a3378a73bc80f7f1ffd5964bf4af356f27c4ddc04e12b26fac5b211b482c|peres|binaries/consent.exe.mui|STRING
graphics/basebrd|dbab41ce0660af5ea665eb17b72bdd20496bdade21b7a055d21dc18ad7295a14|peres|binaries/basebrd.dll|BITMAP
graphics/sidebar|032feb62160f6829306aaefba7ed16edc4887af5aa28db753114b2cfe11b9d3f|peres|binaries/sidebar.exe|BITMAP,RCDATA
graphics/batmeter|e10f89a2c265998a20ad670d39c993409b174f4f29c0f773b42b50236b5b657f|peres|binaries/batmeter.dll|BITMAP
graphics/themecpl|4b5728866ac08e50f19294aab1708c150213600187879b4ec2f20ecb80da2449|peres|binaries/themecpl.dll|UIFILE,XML,BITMAP
graphics/themecpl-strings|2e3af9316962c97cf3f7f32a6492ab9e9feac078f03dc060d868ff796499b841|peres|binaries/themecpl.dll.mui|STRING
graphics/imageres|d6f35b719904ee3387639e320ffba7b8f0a4eebf1f11b93b020a9b5905a80de2|peres|binaries/imageres.dll|IMAGE,PNG,BITMAP
graphics/imageres-ico|bb14f214d1cc6362abc91b29ea346cbde14936f6cb967376899e137994e17ccf|icons|binaries/imageres.dll|16,32,48,256
graphics/shell32-ico|833259cfba1038e9672bf940787034de5d25c6b4cbd6889d818e12af9ad896fc|icons|binaries/shell32.dll|16,32,48,256
graphics/user32-ico|1107abfca2789bfa7ab4dcee415ab987eedb276da8ee1f61da9b10bf012d97b6|icons|binaries/user32.dll|16,32,48
graphics/explorer-ico|050a945298eb7c5350e43b63d83513aadc3475457042c087d322b5e083dce01f|icons|binaries/explorer.exe|16,32,48,256
graphics/consent-ico|514bc90e7ce61d9e1650484d6028b6e43c1b8ac3feada03bd86430d8533c6f0f|icons|binaries/consent.exe|16,32,48,256
icons/windows-vista-cursors|8f5872209b72380c186417923b330a351d81d818702af1eb3fa094a642931d3d|xcursor|cursors|-
gtk/Windows-Vista|b53be6e8c7ca3ae8e3674ad82749cd25aa7c87067baefcda925e1fcf5167985e|gtk|-|Windows-Vista-719b12bdb6f6dd352f7ca26ac2fd78ddc10efb8c
graphics/pnidui-ico|1ecd2b1559d03362939c7ca5251e46d8d15381cf9ef1908fcfe64116cea99cf2|icons|binaries/pnidui.dll|16,32
graphics/sndvolsso-ico|28675bd234eccf5390976982c921fc786e0e7b03bac2b1a58f79844bb22cff13|icons|binaries/sndvolsso.dll|16,32
graphics/bthprops-ico|8d7d9a08e53d5639568513e337f4e4cb0c161fdb88e27988f3e8a74f573ee7d4|icons|binaries/bthprops.cpl|16,32
graphics/timedate|124b693af29608c8dad8ef3caf2d1f7ac2b85792f1d949d785a1bab17339d9fb|peres|binaries/timedate.cpl|PNGFILE,UIFILE
graphics/shell32-strings|5601f961df4a661635a3023658ce3fd6c46f28c993c5d762a7cc7b52b30c8d01|peres|binaries/shell32.dll.mui|STRING,DIALOG
graphics/mmsys-strings|3feb1adf58331e7a6b451e93d40d302ae914f24a7d44b8b880b9f1dcf68981a6|peres|binaries/mmsys.cpl.mui|STRING,DIALOG
graphics/mmsys-ico|8b1fabbf23ab0c6b145ba82051354d9fc51a83c00f877f21d72d310cb919c6a1|icons|binaries/mmsys.cpl|16,32,48
graphics/sndvol-strings|f5d69612eed1c0fd5f167b1623eab7d4981f38b454532122370e8b74198014a3|peres|binaries/sndvol.exe.mui|STRING,DIALOG
graphics/sndvol-ico|2284a046390c5665ff96fc9d1ca586dfff4767ca3ee82504924e36a726503368|icons|binaries/sndvol.exe|16,32,48
graphics/netshell-strings|4df4a379da5a765b9033fb26fc7cf9ceb768c05fa14dd0380449a527aa01b9f4|peres|binaries/netshell.dll.mui|STRING,DIALOG
graphics/netshell-ico|ce3769541ae356152387305ab3f6918a6011cd36efcdfcdc9eba95d5d3e7e22e|icons|binaries/netshell.dll|16,32,48
graphics/bthprops-strings|5a5f81743dca7cca69eefd0633db2a5930f3820321017b2c5cda2c773fb36e55|peres|binaries/bthprops.cpl.mui|STRING,DIALOG
graphics/desk-strings|71ca8655e433a844f817b2ceeeb8b6823fb2c8a23b365c7a7e6a7dee1bffa629|peres|binaries/desk.cpl.mui|STRING,DIALOG
graphics/desk-ico|8b31d00a1df90ae132d63614e5d6fc327e85e3e9b7de2e84b280e0441d77a9e9|icons|binaries/desk.cpl|16,32,48
graphics/desk|82ea5aa0e4976858b50129dade9c6f26f80f482602b00dc9dfc8b62d26f4822e|peres|binaries/desk.cpl|BITMAP,PNGFILE
graphics/van|c1229983469c1b1fb0639d63db352b2303558e3872f835353d7c6cd2e96861ae|peres|binaries/van.dll|BITMAP,PNGFILE,UIFILE
graphics/van-strings|be0095327581cd98b50d185a5754a8825334d76814536e157ea7b47dffdca0cd|peres|binaries/van.dll.mui|STRING,DIALOG,UIFILE
graphics/van-ico|ac79a2e0588740d485f05a57befee17a279826bbda0112bd8fa65b41efddf69d|icons|binaries/van.dll|16,32,48
graphics/wlanpref-strings|22b7c1ccd61ace1ed181b6090a4d7da78bbc1b16872b13a2627a7e7bdc313ff7|peres|binaries/wlanpref.dll.mui|STRING,DIALOG
EOF
)

GTK_URL=https://codeload.github.com/B00merang-Project/Windows-Vista/tar.gz/719b12bdb6f6dd352f7ca26ac2fd78ddc10efb8c
GTK_SHA=6b08f59b9d3910f803c09e7dd4dc2856d1c03e8a4cffe8598e34032c411c4551

err() { echo "  error: $*" >&2; }

hash_of() {  # file -> sha256; directory -> sha256 of its sorted per-file sha256 list (+ links)
    if [[ -d $1 ]]; then
        (cd "$1" && find . -type f -print0 | LC_ALL=C sort -z | xargs -0 -r sha256sum
         find . -type l -printf '%p -> %l\n' | LC_ALL=C sort) | sha256sum | cut -d' ' -f1
    else
        sha256sum "$1" | cut -d' ' -f1
    fi
}

# ── the ISO route: one install.wim, files pulled out by path ──────────────
wim="" wim_index=""
open_iso() {
    [[ -n $wim ]] && return 0
    if ((FROM_ISO)) && [[ -z $ISO ]]; then
        mkdir -p "$ISO_CACHE"
        ISO=$ISO_CACHE/en_windows_vista_sp2_x86_dvd_342266.iso
        if [[ ! -e $ISO.ok ]]; then
            echo "The Vista SP2 DVD image is $((ISO_SIZE / 1000000)) MB, downloaded once to $ISO_CACHE (resumable)."
            [[ -t 0 ]] || { err "--from-iso needs a terminal to confirm the download"; return 1; }
            read -r -p "Download it now? [y/N] " ans
            [[ $ans == [yY] ]] || { err "not downloaded"; return 1; }
            curl -fL -C - -A "$UA" -o "$ISO" "$ISO_URL" || { err "ISO download failed (re-run to resume)"; return 1; }
            [[ $(stat -c %s "$ISO") == "$ISO_SIZE" && $(sha1sum "$ISO" | cut -d' ' -f1) == "$ISO_SHA1" ]] ||
                { err "the ISO does not match its published size/sha1"; return 1; }
            : >"$ISO.ok"
        fi
    fi
    echo "  unpacking sources/install.wim from $ISO" >&2
    7z e -y -o"$WORK/iso" "$ISO" sources/install.wim >/dev/null || { err "7z could not read $ISO"; return 1; }
    wim=$WORK/iso/install.wim
    # The edition the pins were taken from; Business holds every file used.
    wim_index=$(wimlib-imagex info "$wim" | awk -F': *' '/^Index:/ {i=$2} /^Name:/ && tolower($2) ~ /business$/ {print i; exit}')
    [[ -n $wim_index ]] || { err "no Business edition in $ISO"; return 1; }
}

get() {  # path in install.wim -> local file
    local path=$1 out=$WORK/get/$1
    mkdir -p "$(dirname "$out")"
    if [[ -n $ISO ]] || ((FROM_ISO)); then
        open_iso || return 1
        wimlib-imagex extract "$wim" "$wim_index" "/$path" --dest-dir="$(dirname "$out")" --no-acls >/dev/null 2>&1 ||
            { err "not in install.wim: $path"; return 1; }
    else
        curl -sfL --retry 3 -A "$UA" -o "$out" "$BASE$(python3 -Ic 'import sys,urllib.parse;print(urllib.parse.quote(sys.argv[1],safe=""))' "$path")" ||
            { err "download failed: $path"; return 1; }
    fi
    echo "$out"
}

total=$(grep -c . <<<"$FILES")
n=0
while IFS='|' read -r dest sha path; do
    n=$((n + 1))
    target=$ASSETS/$dest
    if [[ -f $target && $(sha256sum "$target" | cut -d' ' -f1) == "$sha" ]]; then
        verified=$((verified + 1)); continue
    fi
    printf '  [%d/%d] %s\n' "$n" "$total" "$dest"
    got=$(get "$path") || { failures+=("not fetched: $dest"); continue; }
    have=$(sha256sum "$got" | cut -d' ' -f1)
    [[ $have == "$sha" ]] || { failures+=("HASH MISMATCH $dest: expected $sha got $have"); continue; }
    mkdir -p "$(dirname "$target")" && mv "$got" "$target"
    fetched=$((fetched + 1))
done <<<"$FILES"

build() {  # method input member -> produced path (inside $WORK)
    local method=$1 in=$ASSETS/$2 member=$3 x
    x=$(mktemp -d "$WORK/x.XXXXXX")
    case $method in
        msstyles) "${VT[@]}" msstyles "$in" "$x/out" || return 1; echo "$x/out" ;;
        wave) "${VT[@]}" wave "$in" "$x/out.wav" "$member" || return 1; echo "$x/out.wav" ;;
        peres) "${VT[@]}" peres "$in" "$x/out" "$member" || return 1; echo "$x/out" ;;
        icons) "${VT[@]}" icons "$in" "$x/out" "$member" || return 1; echo "$x/out" ;;
        xcursor) "${VT[@]}" xcursor "$in" "$ASSETS/binaries/user32.dll" "$x/out" || return 1; echo "$x/out" ;;
        gtk)
            curl -sfL -A "$UA" -o "$x/gtk.tgz" "$GTK_URL" || { err "GTK download failed"; return 1; }
            [[ $(sha256sum "$x/gtk.tgz" | cut -d' ' -f1) == "$GTK_SHA" ]] || { err "GTK tarball hash mismatch"; return 1; }
            bsdtar -xf "$x/gtk.tgz" -C "$x" || return 1
            echo "$x/$member" ;;
        *) err "unknown method $method"; return 1 ;;
    esac
}

while IFS='|' read -r dest sha method src member; do
    target=$ASSETS/$dest
    if [[ -e $target && $(hash_of "$target") == "$sha" ]]; then
        verified=$((verified + 1)); continue
    fi
    echo "  derive: $dest"
    produced=$(build "$method" "$src" "$member") || { failures+=("not derived: $dest"); continue; }
    if [[ -d $produced ]] && escaped=$(find "$produced" -type l -print0 | xargs -0 -r realpath -m -- | grep -v "^$produced/"); then
        failures+=("$dest: symlinks leave the tree: $escaped"); continue
    fi
    got=$(hash_of "$produced")
    [[ $got == "$sha" ]] || { failures+=("HASH MISMATCH $dest: expected $sha got $got"); continue; }
    mkdir -p "$(dirname "$target")" && rm -rf "$target" && mv "$produced" "$target"
done <<<"$DERIVED"

if ((FROM_ISO && !KEEP_ISO)) && [[ -e $ISO_CACHE/en_windows_vista_sp2_x86_dvd_342266.iso.ok ]]; then
    rm -f "$ISO_CACHE"/en_windows_vista_sp2_x86_dvd_342266.iso{,.ok} && echo "deleted the DVD image (keep it with --keep-iso)"
fi

# ── user-level installs of what was fetched ──────────────────────────────
install_tree() {  # assets-relative src, destination dir
    [[ -d $ASSETS/$1 ]] || { failures+=("not installed: $2 ($1 missing)"); return; }
    local sha; sha=$(hash_of "$ASSETS/$1")
    [[ -r $2/.vista-src && $(<"$2/.vista-src") == "$sha" ]] && return
    mkdir -p "$(dirname "$2")" && rm -rf "$2.vista-tmp" && cp -r "$ASSETS/$1" "$2.vista-tmp" &&
        echo "$sha" >"$2.vista-tmp/.vista-src" && rm -rf "$2" && mv "$2.vista-tmp" "$2" &&
        echo "installed: $2" || failures+=("install $2")
}
fontdir=$DATA/fonts/vista
mkdir -p "$fontdir"
changed=0
for f in "$ASSETS"/fonts/*.ttf; do
    cmp -s "$f" "$fontdir/${f##*/}" || { cp "$f" "$fontdir/" && changed=1; }
done
((changed)) && fc-cache -f "$fontdir" >/dev/null && echo "fonts: installed in $fontdir"
install_tree gtk/Windows-Vista "$DATA/themes/Windows Vista"
install_tree icons/windows-vista-cursors "$DATA/icons/windows-vista-cursors"

# Wallpapers: every scheme gets Vista's default, Aurora, and only Aurora:
# img36 (16:10, the closer crop on 16:9 screens) then img24 (4:3). Omarchy
# moves to the next background whenever a theme is set again, so a longer
# list would rotate away from Aurora on every scheme switch. The other
# wallpapers stay in assets/wallpapers/. Replaces the installer's placeholder.
for t in "$HERE"/../themes/windows-vista*/; do
    [[ -d $t ]] || continue
    mkdir -p "$t/backgrounds"
    find "$t/backgrounds" -maxdepth 1 \( -name 'placeholder.png' -o -name '[0-9][0-9]-img*.jpg' \) \
        ! -name '00-img36.jpg' ! -name '01-img24.jpg' -delete
    for pair in 00:36 01:24; do
        src=$ASSETS/wallpapers/img${pair#*:}.jpg link=$t/backgrounds/${pair%%:*}-img${pair#*:}.jpg
        [[ -f $src ]] || continue
        [[ $(readlink "$link" 2>/dev/null) == "$src" ]] || ln -sfn "$src" "$link"
    done
done

"$HERE/bin/vista-art" || failures+=("derived art (vista-art)")

echo "fetch-assets: $verified verified, $fetched fetched, ${#failures[@]} failed"
if ((${#failures[@]})); then
    printf '  FAIL: %s\n' "${failures[@]}" >&2
    exit 1
fi
