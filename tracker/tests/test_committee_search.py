import tempfile
import unittest
from contextlib import closing

from app import Store, create_app, word_prefix_match


class CommitteeSearchTests(unittest.TestCase):
    def test_individual_word_prefixes(self):
        self.assertTrue(word_prefix_match('Citizens for Jimmy Ford', 'FORD'))
        self.assertTrue(word_prefix_match('Citizens for Jimmy Ford', 'jim for'))
        self.assertFalse(word_prefix_match('Affordable Assisted Living Coalition PAC', 'Ford'))
        self.assertFalse(word_prefix_match('AED for Woodford County Board', 'Ford'))
        self.assertFalse(word_prefix_match('Friends of Ford', 'Ford Jones'))
        self.assertTrue(word_prefix_match('Friends of Diaz-Chavez', 'chav'))
        self.assertTrue(word_prefix_match('Friends of O’Brien', 'o’br'))
        self.assertTrue(word_prefix_match('Friends of Ｆｏｒｄ', 'ford'))
        self.assertTrue(word_prefix_match('Any committee', '  '))
        self.assertFalse(word_prefix_match('Any committee', '%'))

    def test_filtering_precedes_pagination(self):
        with tempfile.TemporaryDirectory() as directory:
            client = create_app(directory, poll=False).test_client()
            store = Store(directory)
            with closing(store.connect()) as db, db:
                db.execute('DELETE FROM committees')
                db.executemany('INSERT INTO committees(id,name) VALUES(?,?)',
                               [(f'a{i:03}', 'Affordable Coalition') for i in range(110)] +
                               [(f'b{i:03}', f'Citizens for Ford {i}') for i in range(105)])
            first = client.get('/v1/committees', query_string={'q': 'ford'}).get_json()
            self.assertEqual(len(first['committees']), 100)
            self.assertTrue(first['has_more'])
            second = client.get('/v1/committees', query_string={
                'q': 'ford', 'after': first['next_cursor']}).get_json()
            self.assertEqual(len(second['committees']), 5)
            self.assertFalse(second['has_more'])
            self.assertEqual(len({c['id'] for c in first['committees'] + second['committees']}), 105)


if __name__ == '__main__':
    unittest.main()
