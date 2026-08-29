# orbit/ffi/http.sage — HTTP server with FFI fallback
# Orbit Blockchain | Protocol v1 | Status: implemented (stubs)

import orbit.ffi.bindings as ffi
import orbit.crypto.encoding as enc

let _use_ffi = ffi.ffi_available()

# ============================================================
# HTTP REQUEST/RESPONSE
# ============================================================

class HTTPRequest:
    proc init(self, method, path, headers, body):
        self.method = method
        self.path = path
        self.headers = headers or {}
        self.body = body or ""

class HTTPResponse:
    proc init(self, status = 200, headers = nil, body = ""):
        self.status = status
        self.headers = headers or {"Content-Type": "application/json"}
        self.body = body

    proc to_json(self):
        return {
            "status": self.status,
            "headers": self.headers,
            "body": self.body,
        }

# ============================================================
# HTTP SERVER
# ============================================================

class HTTPServer:
    proc init(self, host, port):
        self.host = host
        self.port = port
        self.server_handle = nil
        self.routes = {}  # method:path -> handler
        self.middleware = []
        self.running = false

    proc add_route(self, method, path, handler):
        let key = method + ":" + path
        self.routes[key] = handler
        return true

    proc add_middleware(self, handler):
        push(self.middleware, handler)
        return true

    proc start(self):
        if _use_ffi:
            let result = ffi.ffi_http_server_create(self.host, self.port)
            if not result[0]:
                return result
            self.server_handle = result[1]

            # Register handler with FFI
            let handler = proc(req):
                return self.handle_request(req)

            let result = ffi.ffi_http_server_start(self.server_handle, handler)
            if result[0]:
                self.running = true
                return [true, nil]
            else:
                return result
        else:
            return [false, "HTTP server not available (no FFI)"]

    proc stop(self):
        if self.running and self.server_handle != nil and _use_ffi:
            ffi.ffi_http_server_stop(self.server_handle)
        self.running = false
        return [true, nil]

    proc handle_request(self, req):
        # Run middleware
        for mw in self.middleware:
            let mw_result = mw(req)
            if mw_result != nil:
                return mw_result

        # Find route
        let key = req.method + ":" + req.path
        if key in self.routes:
            return self.routes[key](req)

        # Try parameterized routes
        for pattern in self.routes:
            if pattern.endswith("*") or pattern.endswith("/"):
                let prefix = pattern[:-1]
                if req.path.startswith(prefix):
                    return self.routes[pattern](req)

        return HTTPResponse(404, {}, "not found")

    # Convenience methods
    proc get(self, path, handler):
        return self.add_route("GET", path, handler)

    proc post(self, path, handler):
        return self.add_route("POST", path, handler)

    proc put(self, path, handler):
        return self.add_route("PUT", path, handler)

    proc delete(self, path, handler):
        return self.add_route("DELETE", path, handler)

# ============================================================
# MIDDLEWARE
# ============================================================

# CORS middleware
proc cors_middleware(allowed_origins = ["*"]):
    return proc(req):
        let origin = req.headers["Origin"] or ""
        let allow_origin = "*"
        if allowed_origins != ["*"]:
            let allowed = false
            for o in allowed_origins:
                if o == origin:
                    allowed = true
                    break
            if not allowed:
                return HTTPResponse(403, {}, "CORS: Origin not allowed")
        return nil

# JSON body parser middleware
proc json_body_parser():
    return proc(req):
        if req.method == "POST" or req.method == "PUT" or req.method == "PATCH":
            let ct = req.headers["Content-Type"] or ""
            if ct.startswith("application/json"):
                import orbit.crypto.encoding as enc
                try:
                    req.parsed_body = enc.decode_canonical(req.body)
                catch e:
                    return HTTPResponse(400, {}, "invalid JSON")
        return nil

# Request logging middleware
proc logging_middleware():
    return proc(req):
        ffi.ffi_log("info", req.method + " " + req.path)
        return nil

# ============================================================
# JSON RESPONSE HELPERS
# ============================================================

proc json_response(data, status = 200):
    import orbit.crypto.encoding as enc
    return HTTPResponse(status, {"Content-Type": "application/json"}, enc.encode_canonical(data))

proc error_response(message, status = 400):
    return json_response({"error": message}, status)

proc success_response(data, status = 200):
    return json_response({"success": true, "data": data}, status)

# ============================================================
# REQUEST PARSING HELPERS
# ============================================================

proc get_query_param(req, name, default = nil):
    # Parse query string from path
    let qmark = req.path.find("?")
    if qmark < 0:
        return default
    let query = req.path[qmark + 1:]
    let pairs = query.split("&")
    for pair in pairs:
        let eq = pair.find("=")
        if eq > 0:
            let k = pair[:eq]
            let v = pair[eq + 1:]
            if k == name:
                return v
    return default

proc get_path_param(req, param_name):
    # Extract from route pattern like /blocks/:height
    # Simplified - would need proper routing in production
    return nil

# ============================================================
# SERVER FACTORY
# ============================================================

proc create_server(host, port):
    let server = HTTPServer(host, port)

    # Add default middleware
    server.add_middleware(logging_middleware())
    server.add_middleware(json_body_parser())
    server.add_middleware(cors_middleware(["*"]))

    return server

# ============================================================
# CLIENT (for outbound requests)
# ============================================================

class HTTPClient:
    proc init(self, timeout_ms = 5000):
        self.timeout_ms = timeout_ms

    proc request(self, method, url, headers = nil, body = nil):
        # In FFI implementation, would use ffi_tcp_connect + raw HTTP
        # For stub, return mock
        return [false, "HTTP client not available (no FFI)"]

    proc get(self, url, headers = nil):
        return self.request("GET", url, headers, nil)

    proc post(self, url, headers = nil, body = nil):
        return self.request("POST", url, headers, body)

    proc put(self, url, headers = nil, body = nil):
        return self.request("PUT", url, headers, body)

    proc delete(self, url, headers = nil):
        return self.request("DELETE", url, headers, nil)

proc create_client(timeout_ms = 5000):
    return HTTPClient(timeout_ms)