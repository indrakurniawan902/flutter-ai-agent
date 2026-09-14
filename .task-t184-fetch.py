import json, urllib.request, tarfile, io, os

os.makedirs('.ref', exist_ok=True)
with urllib.request.urlopen('https://pub.dev/api/packages/flutter_tts', timeout=30) as r:
    meta = json.load(r)
ver = meta['latest']['version']
print('latest version:', ver)
url = meta['latest']['archive_url']
print('archive:', url)
data = urllib.request.urlopen(url, timeout=60).read()
tf = tarfile.open(fileobj=io.BytesIO(data), mode='r:gz')
dest = os.path.join('.ref', 'flutter_tts')
tf.extractall(dest)
print('extracted to', dest)
for f in sorted(os.listdir(os.path.join(dest, 'lib'))):
    print('lib/', f)
