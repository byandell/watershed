"""
CLI Launcher routine and programatic application launcher helper.
"""

import sys
import webbrowser
import uvicorn
from hexmap.app import app


def launch_app(port: int = 8000, host: str = "127.0.0.1", launch_browser: bool = True) -> None:
    """
    Launches the interactive Shiny for Python explorer application.

    Parameters
    ----------
    port : int
        HTTP server port (default: 8000).
    host : str
        Host interface bind address (default: '127.0.0.1').
    launch_browser : bool
        Whether to open the default web browser automatically (default: True).
    """
    url = f"http://{host}:{port}"
    print(f"Launching hexmap interactive explorer at {url}...")
    
    if launch_browser:
        webbrowser.open(url)

    uvicorn.run(app, host=host, port=port)


def main() -> None:
    """
    CLI entrypoint routine for `hexmap-app` script.
    """
    port = 8000
    if len(sys.argv) > 1 and sys.argv[1].isdigit():
        port = int(sys.argv[1])
    
    launch_app(port=port)


if __name__ == "__main__":
    main()
