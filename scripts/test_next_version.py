import unittest

from next_version import bump, notes


class NextVersionTests(unittest.TestCase):
    def test_first_release(self):
        self.assertEqual(bump(None, [("feat: anything", "")]), "1.0.0")

    def test_no_changes_keeps_the_version(self):
        self.assertEqual(bump("1.2.3", []), "1.2.3")

    def test_fix_is_a_patch(self):
        self.assertEqual(bump("1.2.3", [("fix: seeds stay in the store", ""), ("docs: tidy", "")]), "1.2.4")

    def test_feature_is_a_minor(self):
        self.assertEqual(bump("1.2.3", [("fix: x", ""), ("feat(journey): new chapter", "")]), "1.3.0")

    def test_breaking_is_a_major(self):
        self.assertEqual(bump("1.2.3", [("feat!: online play", "")]), "2.0.0")
        self.assertEqual(bump("1.2.3", [("refactor: saves", "BREAKING CHANGE: old saves reset")]), "2.0.0")

    def test_titles_without_the_convention_count_as_a_patch(self):
        self.assertEqual(bump("1.2.3", [("Accessibility: VoiceOver", "")]), "1.2.4")

    def test_notes_group_by_kind(self):
        text = notes([("feat: riddle streak", ""), ("fix(board): rings", ""), ("chore: tidy", "")])
        self.assertIn("New:\n- Riddle streak", text)
        self.assertIn("Fixed:\n- Rings", text)
        self.assertIn("Also:\n- Tidy", text)


    def test_notes_fit_testflight(self):
        text = notes([(f"fix: change number {i} with a fairly long description", "") for i in range(200)])
        self.assertLessEqual(len(text), 3600)
        self.assertTrue(text.endswith("…and more"))


if __name__ == "__main__":
    unittest.main()
