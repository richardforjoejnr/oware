import pathlib
import tempfile
import unittest

from site_pretty_urls import prettify


class PrettyUrlTests(unittest.TestCase):
    def test_pages_get_a_folder_index_and_index_pages_stay(self):
        with tempfile.TemporaryDirectory() as tmp:
            site = pathlib.Path(tmp)
            (site / "lelu-oware").mkdir()
            (site / "index.html").write_text("home")
            (site / "404.html").write_text("missing")
            (site / "lelu-oware" / "index.html").write_text("app")
            (site / "lelu-oware" / "privacy.html").write_text("privacy")
            made = prettify(site)
            self.assertEqual((site / "lelu-oware" / "privacy" / "index.html").read_text(), "privacy")
            self.assertEqual([p.relative_to(site).as_posix() for p in made], ["lelu-oware/privacy/index.html"])
            self.assertFalse((site / "404" / "index.html").exists())


if __name__ == "__main__":
    unittest.main()
