import unittest

from build_release_notes import render


class ReleaseNotesPageTests(unittest.TestCase):
    def test_no_release_yet(self):
        page = render([], "Lelu Oware", "lelu-oware")
        self.assertIn("The first release is on its way", page)

    def test_newest_first_with_groups(self):
        releases = [
            {"name": "Lelu Oware 1.0.0", "tag_name": "v1.0.0", "published_at": "2026-10-01T10:00:00Z", "body": "Also:\n- First release"},
            {"name": "Lelu Oware 1.1.0", "tag_name": "v1.1.0", "published_at": "2026-11-02T10:00:00Z", "body": "New:\n- Riddle streak\nFixed:\n- Rings in portrait"},
            {"name": "Other App 3.0.0", "tag_name": "v3.0.0", "published_at": "2026-12-01T10:00:00Z", "body": "New:\n- Not ours"},
        ]
        page = render(releases, "Lelu Oware", "lelu-oware")
        self.assertLess(page.index("## 1.1.0"), page.index("## 1.0.0"))
        self.assertIn("**New**", page)
        self.assertIn("- Riddle streak", page)
        self.assertIn("_2 November 2026_", page)
        self.assertNotIn("Not ours", page)


if __name__ == "__main__":
    unittest.main()
