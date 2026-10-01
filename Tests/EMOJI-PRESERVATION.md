# Candidate emoji preservation

SourceIn previously replaced all glyph colors (including Apple Color Emoji) with
one gradient. The fix deliberately preserves the **entire candidate/run** when
public text contains emoji or an attachment; mixed text is not selectively tinted.
Unicode 17 Emoji property data is pinned, decoded by composed sequences and UTF-16
scalars. Bare ASCII digits, # and * still receive the gradient. Emoji-capable
symbols, including text-presentation forms, conservatively keep original rendering.
Runs longer than 512 UTF-16 units also keep original rendering to bound work.

All six existing NSString/NSAttributedString drawing hooks, UILabel/WeType and
native TUICandidateLabel capture paths share this policy. A depth guard prevents
nested hooks from tinting protected originals. Native captures propagate public
text protection out to the final bitmap. No private getters or new global hooks
are introduced. Opaque private glyph views without text use chromatic detection
inside the existing bounded RGBA ink-bounds pass (no extra bitmap or pixel pass).
This conservatively preserves colored ordinary text too. Truly grayscale emoji
in a private CoreText-only view without accessible text cannot be distinguished
from grayscale ordinary text; public string/UILabel paths protect these by Unicode.

Tests/EmojiProtectionTests.m compiles the actual production helpers with macOS
Foundation, testing Unicode, attributed attachment, bitmap classification/bounds,
and nested/exception depth restoration. These are not UIKit pixel-rendering tests
and cannot certify real-device private keyboard behavior or frame timing. The
native package builds exercise Logos and iOS compilation on each branch. Existing
safe-branch startup/isolation checks are retained. No SDK install is needed locally.

No package version bump: branch versions and PackageInfo/package assertions remain
unchanged; identify these builds by branch + commit + Actions run, not version alone.
The safe branch continues to exclude PureBlackKeyboard; this patch neither merges
branch features nor changes preference relay behavior.
