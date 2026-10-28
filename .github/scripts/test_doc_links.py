"""Build isolated Markdown with the production link hook and inspect its URLs."""

from html.parser import HTMLParser
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


class Links(HTMLParser):
    def __init__(self):
        super().__init__()
        self.urls = []

    def handle_starttag(self, tag, attrs):
        if tag == "a":
            self.urls.append(dict(attrs)["href"])


class DocumentationLinkTests(unittest.TestCase):
    def test_dangerous_schemes_blocked_and_normal_links_preserved(self):
        repository = Path(__file__).resolve().parents[2]
        with tempfile.TemporaryDirectory(prefix="kareki-doc-links-") as directory:
            root = Path(directory)
            (root / "layouts/_markup").mkdir(parents=True)
            (root / "content").mkdir()
            shutil.copyfile(repository / "layouts/_markup/render-link.html",
                            root / "layouts/_markup/render-link.html")
            (root / "layouts/single.html").write_text("{{ .Content }}")
            (root / "hugo.toml").write_text(
                'baseURL = "https://example.invalid/kareki/"\n'
                '[markup.goldmark.renderer]\nunsafe = false\n'
            )
            (root / "content/target.md").write_text("---\ntitle: Target\n---\nTarget")
            urls = ["javascript:alert(1)", "JaVaScRiPt:alert(1)",
                    "data:text/html,probe", "vbscript:probe",
                    "https://example.com/path?q=1", "mailto:test@example.com",
                    "#section", "target.md?x=1#section"]
            (root / "content/probe.md").write_text(
                "---\ntitle: Probe\n---\n" + "\n\n".join(
                    f"[probe]({url})" for url in urls)
            )
            subprocess.run(["hugo", "--source", str(root)], check=True,
                           capture_output=True, text=True)
            parser = Links()
            parser.feed((root / "public/probe/index.html").read_text())
            self.assertEqual(parser.urls, ["#ZgotmplZ"] * 4 + [
                "https://example.com/path?q=1", "mailto:test@example.com",
                "#section", "/kareki/target/?x=1#section",
            ])


if __name__ == "__main__":
    unittest.main()
