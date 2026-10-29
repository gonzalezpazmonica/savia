"""CodeQL #22 (py/clear-text-logging-sensitive-data) in zeroclaw/host/network_cli.py.

The setup wizard printed the config with wifi_pass shown as "***" plus the
last two characters of the password, leaking part of it to the terminal and
its scrollback. The password must not appear at all in the wizard's output.
"""
import io
import types
import unittest
from contextlib import redirect_stdout
from unittest.mock import patch

from zeroclaw.host import network_cli

PASSWORD = "s3cret-WIFI-QZ"


class PasswordDisplayTests(unittest.TestCase):
    def _run_setup(self):
        out = io.StringIO()
        args = types.SimpleNamespace(port=None, serial="/dev/null")
        with patch.object(network_cli, "detect_ssid", return_value="home"), \
                patch.object(network_cli, "detect_host_ip", return_value="127.0.0.1"), \
                patch("builtins.input", return_value=""), \
                patch.object(network_cli.getpass, "getpass", return_value=PASSWORD), \
                patch.object(network_cli, "deploy_config",
                             return_value=(False, "no device")) as deploy, \
                redirect_stdout(out):
            network_cli.cmd_setup(args)
        return out.getvalue(), deploy

    def test_no_part_of_the_password_is_printed(self):
        output, _deploy = self._run_setup()
        self.assertIn('"wifi_pass": "***"', output)
        self.assertNotIn("QZ", output)
        self.assertNotIn(PASSWORD, output)

    def test_device_still_receives_the_real_password(self):
        _output, deploy = self._run_setup()
        self.assertEqual(deploy.call_args.args[0]["wifi_pass"], PASSWORD)


if __name__ == "__main__":
    unittest.main()
