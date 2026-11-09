import unittest

from tests.stock_speed_harness import RPC_DELAY, measure

EXPECTED_DIGEST = {"hash": 3693219069, "len": 2506, "totals": 2, "standalone": 0, "specs": 2, "days": 14}


class StockSpeedTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.result = measure("after")

    def paths(self, name):
        return [row for row in self.result["log"] if row[1] == name]

    def test_stock_table_numbers_are_the_same_as_before_the_speedup(self):
        self.assertEqual(self.result["digest"], EXPECTED_DIGEST)

    def test_waiting_time_is_close_to_the_server_calculation_time(self):
        self.assertLess(self.result["seconds"], RPC_DELAY + 1.5)

    def test_grade_table_is_read_only_once(self):
        self.assertEqual(len(self.paths("qr_lot_grades_v1300")), 1)

    def test_lot_list_is_not_read_twice_for_the_same_page(self):
        pages = [row[3] for row in self.paths("qr_lots") if row[2] == "" and row[3] != ""]
        self.assertEqual(sorted(pages), ["0", "0", "1000", "1000", "2000"])

    def test_grade_lots_and_movements_are_requested_together(self):
        starts = [row[0] for row in self.result["log"] if row[1] == "qr_lot_movements" or (row[1] == "qr_lots" and row[2].startswith("in."))]
        self.assertEqual(len(starts), 7)
        self.assertLess(max(starts) - min(starts), 0.3)


if __name__ == "__main__":
    unittest.main()
