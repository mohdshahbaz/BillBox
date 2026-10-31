#!/usr/bin/env python3
"""Runs the iPhone's PDF reader (BillBox/Resources/PDFReader/reader.html) in a real browser engine and compares every page
with the Mac's way of reading the same PDF (mac_reference.js). Usage: python3 browser_check.py a.pdf b.pdf ..."""
import asyncio, base64, json, os, subprocess, sys
from playwright.async_api import async_playwright

HERE = os.path.dirname(os.path.abspath(__file__))
READER = os.path.join(HERE, '../../BillBox/Resources/PDFReader/reader.html')

async def main(files):
    mac = json.loads(subprocess.run(['node', '--disable-warning=ExperimentalWarning', os.path.join(HERE, 'mac_reference.js'), *files],
                                    capture_output=True, text=True, check=True).stdout)
    bad = 0
    async with async_playwright() as p:
        b = await p.chromium.launch()
        page = await b.new_page()
        errors = []
        page.on('pageerror', lambda e: errors.append(str(e)))
        await page.goto('file://' + os.path.abspath(READER))
        for f in files:
            b64 = base64.b64encode(open(f, 'rb').read()).decode()
            phone = await page.evaluate('(b) => window.readPdf(b)', b64)
            m = mac[os.path.basename(f)]
            same = phone == m
            bad += 0 if same else 1
            print(f"{'same' if same else 'DIFFERENT'}  {os.path.basename(f)}: {len(phone)} pages (Mac {len(m)})")
        await b.close()
        if errors: print('page errors:', errors)
    sys.exit(1 if bad else 0)

asyncio.run(main(sys.argv[1:]))
