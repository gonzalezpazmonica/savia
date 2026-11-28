# SaviaClaw main.py v0.9 — serial + WiFi + LCD + heartbeat + selftest
import machine, sys, gc, json, time, select
from lib.status import StatusLED
from lib.commands import CommandHandler

led = StatusLED(pin=2)
handler = CommandHandler(led)
lcd = None
heartbeat = None
http_server = None

# Init LCD
try:
    from lib.lcd_i2c import LCD
    lcd = LCD()
    lcd.message('SaviaClaw v0.9', 'Booting...')
except:
    pass

# Self-test
try:
    from lib.selftest import run as selftest
    selftest(lcd)
except:
    pass

# Init heartbeat
try:
    from lib.heartbeat import Heartbeat
    heartbeat = Heartbeat(lcd=lcd, interval_ms=8000)
except:
    pass

# WiFi
try:
    import network
    wlan = network.WLAN(network.STA_IF)
    if wlan.isconnected():
        from lib.wifi_server import MiniHTTPServer
        with open('config.json') as f:
            _tok = json.load(f).get('http_token', '')
        _srv = MiniHTTPServer(handler, port=80, token=_tok)
        ip = _srv.start()  # ValueError sin http_token: solo serie (SE-442 #25)
        http_server = _srv
        if heartbeat:
            heartbeat.set_wifi(ip)
        if lcd:
            lcd.message('WiFi: ' + ip, 'SaviaClaw v0.9')
except:
    pass

if lcd and not http_server:
    lcd.message('SaviaClaw v0.9', 'Serial ready')
led.pulse()
sys.stdout.write('SaviaClaw v0.9 ready\n')

try:
    wdt = machine.WDT(timeout=10000)
except:
    wdt = None

poll = select.poll()
poll.register(sys.stdin, select.POLLIN)
buf = ""

while True:
    if wdt:
        wdt.feed()
    if http_server:
        try:
            http_server.poll()
        except:
            pass
    if heartbeat:
        heartbeat.tick()
    ready = poll.poll(50)
    for obj, ev in ready:
        try:
            ch = sys.stdin.read(1)
            if ch in ('\n', '\r'):
                line = buf.strip()
                buf = ""
                if line:
                    resp = handler.process(line)
                    out = json.dumps(resp)
                    sys.stdout.write(out + '\n')
                    if lcd and resp.get("cmd") != "lcd":
                        lcd.write(resp.get("cmd","?")[:16], 0)
            elif ch:
                buf += ch
        except:
            pass
    gc.collect()
