import os, sys, unittest
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mail_filter as mf

GODADDY = "spf=pass (sender IP is 1.2.3.4) smtp.mailfrom=godaddy.com; dkim=pass (signature was verified) header.d=godaddy.com;dmarc=pass action=none header.from=godaddy.com;compauth=pass reason=100"
AQUA = "spf=pass (sender IP is 1.2.3.4) smtp.mailfrom=aquatuning.de; dkim=pass (signature was verified) header.d=aquatuning.de;dmarc=bestguesspass action=none header.from=aquatuning.de;compauth=pass reason=109"
PRIME = "spf=none (sender IP is 1.2.3.4) smtp.mailfrom=norz48.chelsea3.biz.id; dkim=pass (signature was verified) header.d=chelsea3.biz.id;dmarc=bestguesspass action=none header.from=norz48.chelsea3.biz.id;compauth=pass reason=109"
SPOOF = "spf=fail (sender IP is 1.2.3.4) smtp.mailfrom=evil.example; dkim=none (message not signed) header.d=none;dmarc=fail action=none header.from=rjhdesign.se;compauth=fail reason=000"
NEMARIN = "spf=pass smtp.mailfrom=mailchimpapp.net; dkim=pass header.d=mcsv.net; dmarc=fail action=none header.from=nemarin.se;compauth=fail reason=001"


class T(unittest.TestCase):
    def test_org_domain(self):
        self.assertEqual(mf.org_domain("mail1.weekday.com"), "weekday.com")
        self.assertEqual(mf.org_domain("norz48.chelsea3.biz.id"), "chelsea3.biz.id")
        self.assertEqual(mf.org_domain("a.b.co.uk"), "b.co.uk")
        self.assertEqual(mf.org_domain("x.shop.com.pl"), "shop.com.pl")
        self.assertEqual(mf.org_domain("armada.mil.ec"), "armada.mil.ec")
        self.assertEqual(mf.org_domain("mail.anthropic.com"), "anthropic.com")

    def test_sender_key(self):
        self.assertEqual(mf.sender_key("x@mail1.weekday.com"), "weekday.com")
        self.assertEqual(mf.sender_key("Bob@Gmail.com"), "bob@gmail.com")
        self.assertEqual(mf.sender_key("a@hotmail.se"), "a@hotmail.se")
        self.assertEqual(mf.sender_key("a@outlook.com"), "a@outlook.com")

    def test_auth(self):
        self.assertTrue(mf.auth_aligned(GODADDY, "renewals@godaddy.com"))
        self.assertTrue(mf.auth_aligned(AQUA, "noreply@aquatuning.de"))
        self.assertFalse(mf.auth_aligned(SPOOF, "kontakt@rjhdesign.se"))
        self.assertFalse(mf.auth_aligned(NEMARIN, "info@nemarin.se"))
        self.assertFalse(mf.auth_aligned(GODADDY, "x@paypal.com"))  # header for another domain
        self.assertFalse(mf.auth_aligned(None, "a@b.se"))

    def test_listed(self):
        self.assertTrue(mf.listed("no-reply@mail1.weekday.com", {"weekday.com"}))
        self.assertFalse(mf.listed("x@notweekday.com", {"weekday.com"}))
        self.assertFalse(mf.listed("stranger@gmail.com", {"gmail.com"}))  # never per freemail domain
        self.assertTrue(mf.listed("friend@gmail.com", {"friend@gmail.com"}))

    def test_rescue(self):
        allow, block, known = {"rjhdesign.se"}, {"spam@godaddy.com"}, {"aquatuning.de"}
        self.assertEqual(mf.rescue_reason("noreply@aquatuning.de", AQUA, allow, block, known), "known sender")
        self.assertIsNone(mf.rescue_reason("x@norz48.chelsea3.biz.id", PRIME, allow, block, known))
        self.assertIsNone(mf.rescue_reason("kontakt@rjhdesign.se", SPOOF, allow, block, known))
        self.assertIsNone(mf.rescue_reason("spam@godaddy.com", GODADDY, {"godaddy.com"}, block, known))
        self.assertEqual(mf.rescue_reason("renewals@godaddy.com", GODADDY, {"godaddy.com"}, block, known), "allowlist")

    def test_learn(self):
        self.assertEqual(mf.learn("junk", "inbox", False), "ham")
        self.assertEqual(mf.learn("inbox", "junk", False), "spam")
        self.assertIsNone(mf.learn("junk", "inbox", True))
        self.assertIsNone(mf.learn(None, "junk", False))
        self.assertIsNone(mf.learn("junk", "junk", False))

    def test_lists(self):
        import tempfile
        p = os.path.join(tempfile.mkdtemp(), "l.txt")
        self.assertTrue(mf.add_entry(p, "a.se", "note"))
        self.assertFalse(mf.add_entry(p, "a.se", "again"))
        self.assertEqual(mf.read_list(p), {"a.se"})
        self.assertTrue(mf.remove_entry(p, "a.se"))
        self.assertEqual(mf.read_list(p), set())


if __name__ == "__main__":
    unittest.main()
