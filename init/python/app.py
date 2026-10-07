import os

from flask import Flask
app = Flask(__name__)

@app.route("/")
def hello():
    return "Hello from Python!"

@app.route("/healthz")
def healthz():
    return "ok", 200

@app.route("/readyz")
def readyz():
    return "ok", 200

if __name__ == "__main__":
    # PORT is injected by the k8s deploy template (CONTAINER_PORT); default
    # matches CONTAINER_PORT in init/app.env.
    app.run(host="0.0.0.0", port=int(os.environ.get("PORT", "8080")))