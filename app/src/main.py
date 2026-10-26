import io
import json
import shlex
import sys
import traceback
from contextlib import redirect_stderr, redirect_stdout
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HOST = "127.0.0.1"
PORT = 8765


def send_json(handler, status, payload):
    raw = json.dumps(payload, ensure_ascii=False).encode("utf-8")
    handler.send_response(status)
    handler.send_header("Content-Type", "application/json; charset=utf-8")
    handler.send_header("Content-Length", str(len(raw)))
    handler.send_header("Access-Control-Allow-Origin", "*")
    handler.end_headers()
    handler.wfile.write(raw)


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_args):
        return

    def do_OPTIONS(self):
        self.send_response(204)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Headers", "content-type")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.end_headers()

    def do_GET(self):
        if self.path == "/health":
            send_json(self, 200, {"status": "ok", "python": sys.version.split()[0]})
            return
        send_json(self, 404, {"error": "Not found"})

    def do_POST(self):
        if self.path != "/run":
            send_json(self, 404, {"error": "Not found"})
            return

        try:
            length = int(self.headers.get("Content-Length", "0"))
            body = self.rfile.read(length)
            request = json.loads(body.decode("utf-8"))
            code = request.get("code", "")
            file_name = request.get("fileName", "<PipisTerminal>")
            raw_args = request.get("args", "")

            if not isinstance(code, str):
                raise ValueError("code must be a string")
            if not isinstance(file_name, str) or not file_name.strip():
                raise ValueError("fileName must be a non-empty string")
            if not isinstance(raw_args, str):
                raise ValueError("args must be a string")
            args = shlex.split(raw_args)
        except ValueError as exc:
            send_json(self, 400, {"error": str(exc)})
            return
        except Exception as exc:
            send_json(self, 400, {"error": str(exc)})
            return

        stdout = io.StringIO()
        stderr = io.StringIO()
        exit_code = 0
        namespace = {
            "__name__": "__main__",
            "__file__": file_name,
        }
        original_argv = sys.argv

        try:
            sys.argv = [file_name, *args]
            with redirect_stdout(stdout), redirect_stderr(stderr):
                exec(compile(code, file_name, "exec"), namespace, namespace)
        except SystemExit as exc:
            value = exc.code
            exit_code = value if isinstance(value, int) else 0
            if value not in (None, 0):
                print(value, file=stderr)
        except BaseException:
            exit_code = 1
            traceback.print_exc(file=stderr)
        finally:
            sys.argv = original_argv

        send_json(
            self,
            200,
            {
                "stdout": stdout.getvalue(),
                "stderr": stderr.getvalue(),
                "exitCode": exit_code,
                "fileName": file_name,
                "args": args,
            },
        )


if __name__ == "__main__":
    server = ThreadingHTTPServer((HOST, PORT), Handler)
    server.serve_forever()
