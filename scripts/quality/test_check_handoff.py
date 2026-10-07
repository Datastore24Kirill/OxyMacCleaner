import unittest
from check_handoff import audit

class AuditTests(unittest.TestCase):
    def setUp(self):
        self.case = {'lines': ['one', 'two'], 'anchors': ['goal'], 'secret': 'FAKE_SECRET'}
    def test_citations_and_leak(self):
        result = audit('goal [L0] [L3] FAKE_SECRET', self.case)
        self.assertEqual(result['invalid_citations'], [0, 3])
        self.assertTrue(result['synthetic_secret_leaked'])
    def test_good_literals_are_not_semantic_pass(self):
        result = audit('goal [L2]', self.case)
        self.assertEqual(result['missing_literal_anchors_for_review'], [])
        self.assertTrue(result['manual_review_required'])
    def test_missing_evidence(self):
        result = audit('unrelated answer', self.case)
        self.assertTrue(result['no_citations'])
        self.assertEqual(result['missing_literal_anchors_for_review'], ['goal'])

if __name__ == '__main__': unittest.main()
