import unittest

import os
import subprocess
import tempfile

from next_version import APP_PATHS, bump, current_app, notes, store_notes, titles_since


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

    def test_breaking_change_with_a_hyphen(self):
        self.assertEqual(bump("1.2.3", [("fix: saves", "BREAKING-CHANGE: old saves reset")]), "2.0.0")
        self.assertEqual(bump("1.2.3", [("docs: tidy", "BREAKING-CHANGE: links moved")]), "2.0.0")

    def test_titles_without_the_convention_count_as_a_patch(self):
        self.assertEqual(bump("1.2.3", [("Accessibility: VoiceOver", "")]), "1.2.4")

    def test_capitalised_types_from_before_the_convention(self):
        old = [("Docs: App Store text up to date", ""), ("CI signing: profile for the app target", "")]
        self.assertEqual(bump("1.2.3", old[:1]), "1.2.3", "Docs: is still docs")
        self.assertEqual(bump("1.2.3", [("Feat: journey", "")]), "1.3.0")
        text = notes(old + [("Accessibility: VoiceOver", ""), ("Fix: rings", "")])
        self.assertNotIn("App Store text", text)
        self.assertIn("Fixed:\n- Rings", text)
        self.assertIn("- CI signing: profile for the app target", text, "unknown types keep the whole title")
        self.assertIn("- Accessibility: VoiceOver", text)

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


    def test_store_notes_list_only_what_players_notice(self):
        text = store_notes([("feat: riddle streak", ""), ("fix(board): rings", ""), ("perf: faster AI", ""),
                            ("refactor: saves", ""), ("chore: tidy", ""), ("Milestone 2: core", "")])
        self.assertEqual(text, "- Riddle streak\n- Rings\n- Faster AI")

    def test_store_notes_are_never_empty(self):
        self.assertEqual(store_notes([("refactor: saves", ""), ("ci: cache", "")]), "Small fixes and improvements.")

    def test_store_notes_fit_the_app_store(self):
        text = store_notes([(f"fix: change number {i} with a fairly long description", "") for i in range(200)])
        self.assertLessEqual(len(text), 4000)
        self.assertTrue(text.endswith("…and more"))


class PerAppTests(unittest.TestCase):
    """Two apps in one repository: each counts only the changes to its own files."""

    def test_the_app_comes_from_the_folder_or_the_flag(self):
        self.assertEqual(current_app([], "/repo/apps/lelu-oware"), "lelu-oware")
        self.assertEqual(current_app([], "/repo/apps/lelu-ludo/fastlane"), "lelu-ludo")
        self.assertEqual(current_app(["--app=lelu-ludo"], "/repo"), "lelu-ludo")
        self.assertIsNone(current_app([], "/repo"), "the whole repository, as before")
        self.assertIsNone(current_app([], "/repo/apps/unknown"))

    def test_a_ludo_change_never_counts_for_oware(self):
        with tempfile.TemporaryDirectory() as repo:
            def run(*args):
                subprocess.run(["git", *args], cwd=repo, check=True, capture_output=True)
            run("init", "-q", "-b", "main")
            run("config", "user.email", "t@example.com"); run("config", "user.name", "T")
            for path, title in [("apps/lelu-oware/a.txt", "fix: oware board"),
                                ("apps/lelu-ludo/b.txt", "feat: ludo dice"),
                                ("packages/SupportKit/c.txt", "fix: tip jar"),
                                ("docs/d.txt", "docs: readme")]:
                os.makedirs(os.path.join(repo, os.path.dirname(path)), exist_ok=True)
                with open(os.path.join(repo, path), "w") as f:
                    f.write(title)
                run("add", path); run("commit", "-q", "-m", title)
            here = os.getcwd()
            os.chdir(repo)
            try:
                oware = [t for t, _ in titles_since(None, APP_PATHS["lelu-oware"])]
                ludo = [t for t, _ in titles_since(None, APP_PATHS["lelu-ludo"])]
                everything = [t for t, _ in titles_since(None)]
            finally:
                os.chdir(here)
            self.assertEqual(oware, ["fix: tip jar", "fix: oware board"])
            self.assertEqual(ludo, ["fix: tip jar", "feat: ludo dice"], "a shared package counts for both")
            self.assertEqual(len(everything), 4)
            self.assertEqual(bump("1.0.0", [(t, "") for t in oware]), "1.0.1", "Ludo's feat does not make Oware 1.1.0")


if __name__ == "__main__":
    unittest.main()
