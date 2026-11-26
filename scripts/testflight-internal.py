#!/usr/bin/env python3
"""Upload the checked-out commit as an internal-only TestFlight build.

Archives the app with a free marketing version and the next app-wide build number,
uploads it marked as internal-only (never eligible for App Review or external testing),
waits until Apple has processed it, sets export compliance and the "What to Test" note,
and waits until the internal tester group can install it.

Every run is an App Store Connect upload and needs the owner's explicit consent.
Run it inside the checkout to build: the source is that checkout's HEAD,
which must be clean and pushed to origin; any branch is allowed.
The version and build number are passed to xcodebuild only and never committed.

Setup:
  Config/Local.xcconfig
      PRODUCT_BUNDLE_IDENTIFIER and DEVELOPMENT_TEAM of the app's App Store Connect record.
  ~/.config/app-store-connect/config.json
      {"key_id": "...", "issuer_id": "...", "key_path": "..."} for an App Store Connect
      API key that may upload builds. The key is used for signing and never printed.
"""

import argparse
import base64
import json
from pathlib import Path
import plistlib
import re
import subprocess
import sys
import time
import urllib.error
import urllib.request


PROJECT = 'Lined.xcodeproj'
SCHEME = 'Lined'
DEFAULT_GROUP = 'Intern'
ASC_CONFIG = Path.home() / '.config' / 'app-store-connect' / 'config.json'
API_BASE = 'https://api.appstoreconnect.apple.com'
# App Store versions in these states can still receive builds; every other state closes its version train.
OPEN_VERSION_STATES = {'PREPARE_FOR_SUBMISSION', 'DEVELOPER_REJECTED', 'REJECTED', 'METADATA_REJECTED', 'INVALID_BINARY'}
INSTALLABLE_STATES = {'IN_BETA_TESTING'}
FAILED_BETA_STATES = {'PROCESSING_EXCEPTION', 'EXPIRED'}


def parse_version(text):
    if not re.fullmatch(r'\d+(\.\d+){0,2}', text or ''):
        raise ValueError(f'Invalid marketing version: {text!r}')
    parts = [int(part) for part in text.split('.')]
    return tuple(parts + [0] * (3 - len(parts)))


def choose_version(project_version, store_versions):
    """Returns the project's version unless its train is closed; then the patch after the highest closed version."""
    candidate = parse_version(project_version)
    closed = [parse_version(v['versionString']) for v in store_versions if v['state'] not in OPEN_VERSION_STATES]
    if not closed:
        return project_version
    major, minor, patch = max(closed)
    successor = (major, minor, patch + 1)
    return project_version if candidate >= successor else '.'.join(str(part) for part in successor)


def require_open_version(version, store_versions):
    for store_version in store_versions:
        if parse_version(store_version['versionString']) == parse_version(version) and store_version['state'] not in OPEN_VERSION_STATES:
            raise ValueError(f'Version {version} is already {store_version["state"]} in the App Store and takes no more builds.')


def next_build_number(build_numbers):
    """Build numbers rise across the whole app, so internal and store builds never share one."""
    highest = 0
    for number in build_numbers:
        if not re.fullmatch(r'\d+', number):
            raise ValueError(f'Unexpected build number in App Store Connect: {number!r}')
        highest = max(highest, int(number))
    return str(highest + 1)


def require_signing_identity(settings):
    bundle_id = settings.get('PRODUCT_BUNDLE_IDENTIFIER', '')
    team = settings.get('DEVELOPMENT_TEAM', '')
    if not team or not bundle_id or bundle_id.startswith('com.example.'):
        raise ValueError('Config/Local.xcconfig must set PRODUCT_BUNDLE_IDENTIFIER and DEVELOPMENT_TEAM '
                         'to the app record in App Store Connect.')
    return bundle_id, team


def git(*args):
    return subprocess.run(['git', *args], check=True, capture_output=True, text=True).stdout.strip()


def source_root():
    return Path(git('rev-parse', '--show-toplevel'))


def require_pushed_clean_source():
    if git('status', '--porcelain'):
        raise ValueError('The working tree is not clean. Commit or discard the changes.')
    git('fetch', '--quiet', 'origin')
    sha = git('rev-parse', 'HEAD')
    if not git('branch', '--remotes', '--contains', sha):
        raise ValueError(f'Commit {sha[:12]} is on no branch of origin. Push it first.')
    branch = git('branch', '--show-current') or 'detached'
    return sha, branch


def build_settings(root):
    subprocess.run(['xcodegen', 'generate', '--quiet'], check=True, capture_output=True, text=True, cwd=root)
    output = subprocess.run(
        ['xcodebuild', '-project', str(root / PROJECT), '-target', SCHEME, '-configuration', 'Release', '-showBuildSettings', '-json'],
        check=True, capture_output=True, text=True).stdout
    return json.loads(output)[0]['buildSettings']


def api_key():
    try:
        return json.loads(ASC_CONFIG.read_text())
    except FileNotFoundError:
        raise ValueError(f'{ASC_CONFIG} is missing. It holds the App Store Connect API key; see --help.') from None


def base64url(data):
    return base64.urlsafe_b64encode(data).rstrip(b'=').decode()


def raw_signature(der):
    """Converts an ASN.1 ECDSA signature into the fixed-width r||s form that JWT expects."""
    index = 2 if der[1] < 0x80 else 2 + (der[1] & 0x7F)
    parts = []
    for _ in range(2):
        length = der[index + 1]
        value = der[index + 2:index + 2 + length].lstrip(b'\x00')
        parts.append(value.rjust(32, b'\x00'))
        index += 2 + length
    return b''.join(parts)


def api_token():
    key = api_key()
    now = int(time.time())
    header = {'alg': 'ES256', 'kid': key['key_id'], 'typ': 'JWT'}
    payload = {'iss': key['issuer_id'], 'iat': now, 'exp': now + 600, 'aud': 'appstoreconnect-v1'}
    signing_input = f'{base64url(json.dumps(header).encode())}.{base64url(json.dumps(payload).encode())}'
    signature = subprocess.run(['openssl', 'dgst', '-sha256', '-sign', str(Path(key['key_path']).expanduser())],
                               input=signing_input.encode(), capture_output=True, check=True).stdout
    return f'{signing_input}.{base64url(raw_signature(signature))}'


def asc(method, path, body=None):
    request = urllib.request.Request(
        API_BASE + path.removeprefix(API_BASE), method=method,
        data=None if body is None else json.dumps(body).encode(),
        headers={'Authorization': f'Bearer {api_token()}', 'Content-Type': 'application/json'})
    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            raw = response.read()
    except urllib.error.HTTPError as error:
        raise ValueError(f'App Store Connect {method} {path} failed with HTTP {error.code}: '
                         f'{error.read().decode(errors="replace").strip()}') from None
    except urllib.error.URLError as error:
        raise ValueError(f'App Store Connect {method} {path} failed: {error.reason}') from None
    return json.loads(raw) if raw.strip() else {}


def asc_all(path):
    items = []
    while path:
        page = asc('GET', path)
        items += page['data']
        path = page.get('links', {}).get('next')
    return items


def find_app(bundle_id):
    for app in asc_all(f'/v1/apps?filter[bundleId]={bundle_id}&fields[apps]=bundleId,name,primaryLocale'):
        if app['attributes']['bundleId'] == bundle_id:
            return app
    raise ValueError(f'App Store Connect has no app with the bundle identifier {bundle_id}.')


def store_versions(app_id):
    versions = asc_all(f'/v1/apps/{app_id}/appStoreVersions?filter[platform]=IOS&fields[appStoreVersions]=versionString,appVersionState&limit=200')
    return [{'versionString': v['attributes']['versionString'], 'state': v['attributes']['appVersionState']} for v in versions]


def uploaded_build_numbers(app_id):
    builds = asc_all(f'/v1/builds?filter[app]={app_id}&fields[builds]=version&limit=200')
    return [b['attributes']['version'] for b in builds]


def internal_group(app_id, name):
    for group in asc_all(f'/v1/apps/{app_id}/betaGroups?limit=200'):
        if group['attributes']['name'] == name and group['attributes']['isInternalGroup']:
            return group
    raise ValueError(f'The app has no internal TestFlight group named "{name}".')


def xcode_auth_flags():
    key = api_key()
    return [
        '-allowProvisioningUpdates',
        '-authenticationKeyPath', str(Path(key['key_path']).expanduser()),
        '-authenticationKeyID', key['key_id'],
        '-authenticationKeyIssuerID', key['issuer_id'],
    ]


def run_logged(command, log_path, env=None):
    with log_path.open('w') as log:
        result = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, env=env)
    if result.returncode:
        raise ValueError(f'{command[0]} failed (exit {result.returncode}), log: {log_path}')


def archive_and_upload(root, team, version, build, work_dir):
    work_dir.mkdir(parents=True, exist_ok=True)
    archive = work_dir / f'{SCHEME}.xcarchive'
    auth = xcode_auth_flags()
    print(f'Archiving {version} ({build}). Log: {work_dir / "archive.log"}', flush=True)
    run_logged([
        'xcodebuild', '-project', str(root / PROJECT), '-scheme', SCHEME, '-configuration', 'Release',
        '-destination', 'generic/platform=iOS', '-archivePath', str(archive),
        '-derivedDataPath', str(work_dir / 'DerivedData'), *auth,
        f'MARKETING_VERSION={version}', f'CURRENT_PROJECT_VERSION={build}', 'archive',
    ], work_dir / 'archive.log')

    info = plistlib.loads((archive / 'Info.plist').read_bytes())['ApplicationProperties']
    if (info['CFBundleShortVersionString'], info['CFBundleVersion']) != (version, build):
        raise ValueError(f'The archive carries {info["CFBundleShortVersionString"]} ({info["CFBundleVersion"]}) instead of {version} ({build}).')

    options = work_dir / 'ExportOptions.plist'
    options.write_bytes(plistlib.dumps({
        'method': 'app-store-connect',
        'destination': 'upload',
        'signingStyle': 'automatic',
        'teamID': team,
        'manageAppVersionAndBuildNumber': False,
        'testFlightInternalTestingOnly': True,
        'uploadSymbols': True,
    }))
    print(f'Uploading (internal testing only). Log: {work_dir / "upload.log"}', flush=True)
    # The export copies with rsync and fails with other builds of it than the system's.
    env = {'PATH': '/usr/bin:/bin:/usr/sbin:/sbin', 'HOME': str(Path.home())}
    run_logged([
        'xcodebuild', '-exportArchive', '-archivePath', str(archive), '-exportOptionsPlist', str(options),
        '-exportPath', str(work_dir / 'export'), *auth,
    ], work_dir / 'upload.log', env=env)


def poll(description, check, timeout, interval=30):
    deadline = time.monotonic() + timeout
    while True:
        result = check()
        if result is not None:
            return result
        if time.monotonic() > deadline:
            raise ValueError(f'Timed out: {description}.')
        time.sleep(interval)


def find_processed_build(app_id, version, build):
    def check():
        builds = asc('GET', f'/v1/builds?filter[app]={app_id}&filter[version]={build}'
                            f'&filter[preReleaseVersion.version]={version}&fields[builds]=processingState,usesNonExemptEncryption')['data']
        if not builds:
            return None
        state = builds[0]['attributes']['processingState']
        if state in {'FAILED', 'INVALID'}:
            raise ValueError(f'Apple processed the build as {state}.')
        return builds[0] if state == 'VALID' else None
    print('Waiting for Apple to process the build …', flush=True)
    return poll('processing of the build', check, timeout=90 * 60)


def prepare_for_testers(app, build, group, notes):
    build_id = build['id']
    if build['attributes'].get('usesNonExemptEncryption') is None:
        asc('PATCH', f'/v1/builds/{build_id}', {'data': {'type': 'builds', 'id': build_id, 'attributes': {'usesNonExemptEncryption': False}}})

    localizations = asc('GET', f'/v1/builds/{build_id}/betaBuildLocalizations')['data']
    for localization in localizations:
        asc('PATCH', f'/v1/betaBuildLocalizations/{localization["id"]}',
            {'data': {'type': 'betaBuildLocalizations', 'id': localization['id'], 'attributes': {'whatsNew': notes}}})
    if not localizations:
        asc('POST', '/v1/betaBuildLocalizations', {'data': {
            'type': 'betaBuildLocalizations', 'attributes': {'locale': app['attributes']['primaryLocale'], 'whatsNew': notes},
            'relationships': {'build': {'data': {'type': 'builds', 'id': build_id}}},
        }})

    if not group['attributes']['hasAccessToAllBuilds']:
        asc('POST', f'/v1/betaGroups/{group["id"]}/relationships/builds', {'data': [{'type': 'builds', 'id': build_id}]})

    def check():
        state = asc('GET', f'/v1/builds/{build_id}/buildBetaDetail')['data']['attributes']['internalBuildState']
        if state in FAILED_BETA_STATES:
            raise ValueError(f'TestFlight reports {state}.')
        return state if state in INSTALLABLE_STATES else None
    print('Waiting until the group can install the build …', flush=True)
    return poll('release to the internal testers', check, timeout=30 * 60, interval=15)


def default_notes(branch, sha):
    subject = git('log', '-1', '--format=%s', sha)
    return f'Internal test build of {branch} ({sha[:7]}): {subject}'


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--version', help='marketing version; default: the project\'s, or the next patch after the highest '
                                          'App Store version once the project\'s version is in review or released')
    parser.add_argument('--notes', help='"What to Test" for the testers; default: branch, commit and commit subject')
    parser.add_argument('--group', default=DEFAULT_GROUP, help=f'name of the internal tester group; default: "{DEFAULT_GROUP}"')
    parser.add_argument('--dry-run', action='store_true', help='check the source and print version and build; upload nothing')
    parser.add_argument('--print-next-build', action='store_true',
                        help='print only the next free app-wide build number (also for App Store releases)')
    args = parser.parse_args()
    try:
        root = source_root()
        settings = build_settings(root)
        bundle_id, team = require_signing_identity(settings)
        app = find_app(bundle_id)
        build = next_build_number(uploaded_build_numbers(app['id']))
        if args.print_next_build:
            print(build)
            return 0
        sha, branch = require_pushed_clean_source()
        versions = store_versions(app['id'])
        version = args.version or choose_version(settings['MARKETING_VERSION'], versions)
        require_open_version(version, versions)
        group = internal_group(app['id'], args.group)
        notes = args.notes or default_notes(branch, sha)
        print(f'Source {branch} @ {sha[:12]}, version {version} ({build}), group "{args.group}".', flush=True)
        if args.dry_run:
            return 0
        archive_and_upload(root, team, version, build, root / '.build' / 'testflight' / f'{version}-{build}')
        processed = find_processed_build(app['id'], version, build)
        state = prepare_for_testers(app, processed, group, notes)
        print(json.dumps({'version': version, 'build': build, 'buildId': processed['id'], 'source': sha,
                          'branch': branch, 'internalBuildState': state}, indent=2))
    except (ValueError, OSError, KeyError) as error:
        print(f'Error: {error}', file=sys.stderr)
        return 1
    except subprocess.CalledProcessError as error:
        print(f'{error.cmd[0]} failed (exit {error.returncode}): {error.stderr}', file=sys.stderr)
        return 1
    except KeyboardInterrupt:
        print('\nCancelled.', file=sys.stderr)
        return 130
    return 0


if __name__ == '__main__':
    sys.exit(main())
