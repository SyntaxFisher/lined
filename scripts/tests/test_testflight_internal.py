import importlib.util
from pathlib import Path
import unittest
from unittest.mock import patch


SCRIPT = Path(__file__).resolve().parents[1] / 'testflight-internal.py'
SPEC = importlib.util.spec_from_file_location('testflight_internal', SCRIPT)
testflight = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(testflight)


def version(text, state='READY_FOR_DISTRIBUTION'):
    return {'versionString': text, 'state': state}


class VersionTests(unittest.TestCase):
    def test_keeps_project_version_before_the_first_store_release(self):
        self.assertEqual(testflight.choose_version('0.1.0', [version('1.0', 'PREPARE_FOR_SUBMISSION')]), '0.1.0')

    def test_keeps_project_version_while_its_train_is_open(self):
        versions = [version('1.6.1'), version('1.7', 'PREPARE_FOR_SUBMISSION')]
        self.assertEqual(testflight.choose_version('1.7', versions), '1.7')

    def test_moves_past_a_released_project_version(self):
        versions = [version('1.6'), version('1.6.1'), version('1.5')]
        self.assertEqual(testflight.choose_version('1.6.1', versions), '1.6.2')

    def test_treats_a_version_in_review_as_closed(self):
        versions = [version('1.7', 'WAITING_FOR_REVIEW')]
        self.assertEqual(testflight.choose_version('1.7', versions), '1.7.1')

    def test_compares_versions_numerically(self):
        versions = [version('1.10'), version('1.9.3')]
        self.assertEqual(testflight.choose_version('1.2', versions), '1.10.1')

    def test_rejects_an_explicit_closed_version(self):
        with self.assertRaises(ValueError):
            testflight.require_open_version('1.6', [version('1.6.0')])
        testflight.require_open_version('1.7', [version('1.6.1'), version('1.7', 'DEVELOPER_REJECTED')])

    def test_rejects_malformed_versions(self):
        for text in ['', '1.2.3.4', 'v1.2', '1..2']:
            with self.assertRaises(ValueError):
                testflight.parse_version(text)


class BuildNumberTests(unittest.TestCase):
    def test_next_build_rises_across_all_versions(self):
        self.assertEqual(testflight.next_build_number(['1', '4', '2', '3']), '5')
        self.assertEqual(testflight.next_build_number([]), '1')

    def test_rejects_dotted_build_numbers(self):
        with self.assertRaises(ValueError):
            testflight.next_build_number(['1', '2.1'])


class SigningIdentityTests(unittest.TestCase):
    def test_accepts_a_configured_identity(self):
        settings = {'PRODUCT_BUNDLE_IDENTIFIER': 'org.sample.notes', 'DEVELOPMENT_TEAM': 'ABCDE12345'}
        self.assertEqual(testflight.require_signing_identity(settings), ('org.sample.notes', 'ABCDE12345'))

    def test_rejects_the_placeholder_bundle_identifier(self):
        with self.assertRaises(ValueError):
            testflight.require_signing_identity({'PRODUCT_BUNDLE_IDENTIFIER': 'com.example.lined', 'DEVELOPMENT_TEAM': 'ABCDE12345'})

    def test_rejects_a_missing_team(self):
        with self.assertRaises(ValueError):
            testflight.require_signing_identity({'PRODUCT_BUNDLE_IDENTIFIER': 'org.sample.notes', 'DEVELOPMENT_TEAM': ''})


class SourceTests(unittest.TestCase):
    def test_rejects_dirty_tree(self):
        with patch.object(testflight, 'git', side_effect=lambda *args: ' M file' if args[0] == 'status' else ''):
            with self.assertRaises(ValueError):
                testflight.require_pushed_clean_source()

    def test_rejects_unpushed_commit(self):
        answers = {'status': '', 'fetch': '', 'rev-parse': 'a' * 40, 'branch': ''}
        with patch.object(testflight, 'git', side_effect=lambda *args: answers[args[0]]):
            with self.assertRaises(ValueError):
                testflight.require_pushed_clean_source()

    def test_accepts_pushed_feature_branch(self):
        def git(*args):
            if args[:2] == ('branch', '--remotes'):
                return 'origin/feat/example'
            if args[:2] == ('branch', '--show-current'):
                return 'feat/example'
            return {'status': '', 'fetch': '', 'rev-parse': 'b' * 40}[args[0]]
        with patch.object(testflight, 'git', side_effect=git):
            self.assertEqual(testflight.require_pushed_clean_source(), ('b' * 40, 'feat/example'))


class SignatureTests(unittest.TestCase):
    def test_pads_and_trims_both_integers_to_32_bytes(self):
        r = b'\x00' + b'\x80' + b'\x11' * 31
        s = b'\x22' * 31
        der = bytes([0x30, 4 + len(r) + len(s), 0x02, len(r)]) + r + bytes([0x02, len(s)]) + s
        self.assertEqual(testflight.raw_signature(der), b'\x80' + b'\x11' * 31 + b'\x00' + b'\x22' * 31)


if __name__ == '__main__':
    unittest.main()
