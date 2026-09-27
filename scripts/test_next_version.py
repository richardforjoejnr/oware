import unittest

from next_version import bump, notes


class NextVersionTests(unittest.TestCase):
    def test_first_release(self):
        self.assertEqual(bump(None, [("feat: anything", "")]), "1.0.0")

    def test_no_changes_keeps_the_version(self):
        self.assertEqual(bump("1.2.3", []), "1.2.3")

    def test_fix_is_a_patch(self):
        self.assertEqual(bump("1.2.3", [("fix: seeds stay in the store", ""), ("docs: tidy", "")]), "1.2.4")

    def test_docs_and_chores_alone_make_no_release(self):
        quiet = [("docs: what's new page", ""), ("chore: tidy", ""), ("ci: faster runs", ""), ("test: more cases", "")]
        self.assertEqual(bump("1.2.3", quiet), "1.2.3")
        self.assertEqual(notes(quiet), "")

    def test_a_beta_never_reuses_the_released_version(self):
        self.assertEqual(bump("1.2.3", [("chore: bump a package", "")], for_build=True), "1.2.4")
        self.assertEqual(bump("1.2.3", [], for_build=True), "1.2.3", "nothing new: nothing to build")

    def test_breaking_change_in_a_chore_still_counts(self):
        self.assertEqual(bump("1.2.3", [("chore!: drop iOS 17", "")]), "2.0.0")

    def test_feature_is_a_minor(self):
        self.assertEqual(bump("1.2.3", [("fix: x", ""), ("feat(journey): new chapter", "")]), "1.3.0")

    def test_breaking_is_a_major(self):
        self.assertEqual(bump("1.2.3", [("feat!: online play", "")]), "2.0.0")
        self.assertEqual(bump("1.2.3", [("refactor: saves", "BREAKING CHANGE: old saves reset")]), "2.0.0")

    def test_titles_without_the_convention_count_as_a_patch(self):
        self.assertEqual(bump("1.2.3", [("Accessibility: VoiceOver", "")]), "1.2.4")

    def test_notes_group_by_kind(self):
        text = notes([("feat: riddle streak", ""), ("fix(board): rings", ""), ("refactor: saves", ""), ("chore: tidy", "")])
        self.assertIn("New:\n- Riddle streak", text)
        self.assertIn("Fixed:\n- Rings", text)
        self.assertIn("Also:\n- Saves", text)
        self.assertNotIn("Tidy", text, "chores are not release notes")


    def test_notes_fit_testflight(self):
        text = notes([(f"fix: change number {i} with a fairly long description", "") for i in range(200)])
        self.assertLessEqual(len(text), 3600)
        self.assertTrue(text.endswith("…and more"))


if __name__ == "__main__":
    unittest.main()
