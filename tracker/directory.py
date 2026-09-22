"""Publisher-reviewed directory. Edit directory.json to revise the public lists."""
import json
from pathlib import Path


def load_directory():
    directory = json.loads(Path(__file__).with_name('directory.json').read_text())
    ids = [g['id'] for g in directory['groups']]
    if len(ids) != len(set(ids)):
        raise ValueError('Duplicate directory group')
    return directory


def sync_directory(db, directory):
    """Replace curated memberships without changing individual subscriptions/history."""
    caucus_keys = set()
    for group in directory['groups']:
        keys = set()
        for entry in group['pinned'] + group['members']:
            committee = entry['committee']
            if committee is None:
                continue
            db.execute('INSERT OR IGNORE INTO committees(id,name) VALUES (?,?)',
                       (committee['id'], committee['name']))
            keys.add(committee['id'])
        for entry in group['pinned']:
            if entry['role'] != 'Leader' and entry['committee']:
                caucus_keys.add(entry['committee']['id'])
        db.execute('UPDATE categories SET verified=1,reviewed_at=? WHERE id=?',
                   (directory['revision'], group['id']))
        db.execute('DELETE FROM category_members WHERE category_id=?', (group['id'],))
        db.executemany('INSERT INTO category_members VALUES (?,?)',
                       [(group['id'], key) for key in sorted(keys)])
    db.execute("UPDATE categories SET verified=1,reviewed_at=? WHERE id='caucus-committees'",
               (directory['revision'],))
    db.execute("DELETE FROM category_members WHERE category_id='caucus-committees'")
    db.executemany("INSERT INTO category_members VALUES ('caucus-committees',?)",
                   [(key,) for key in sorted(caucus_keys)])
