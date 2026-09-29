#include "render/gl.hpp"

namespace ds::gl {

bool load(std::string* missing) {
  bool ok = true;
#define X(name)                                                                                        \
  name = reinterpret_cast<decltype(name)>(SDL_GL_GetProcAddress("gl" #name));                          \
  if (!name) { ok = false; if (missing && missing->empty()) *missing = "gl" #name; }
  DS_GL_FUNCS(X)
#undef X
  return ok;
}

static GLuint compile(GLenum type, const char* src, std::string* err) {
  GLuint s = CreateShader(type);
  ShaderSource(s, 1, &src, nullptr);
  CompileShader(s);
  GLint ok = 0;
  GetShaderiv(s, GL_COMPILE_STATUS, &ok);
  if (!ok) {
    char log[2048];
    GetShaderInfoLog(s, sizeof log, nullptr, log);
    if (err) *err = std::string(type == GL_VERTEX_SHADER ? "vertex shader: " : "fragment shader: ") + log;
    DeleteShader(s);
    return 0;
  }
  return s;
}

GLuint make_program(const char* vs, const char* fs, std::string* err) {
  GLuint v = compile(GL_VERTEX_SHADER, vs, err);
  if (!v) return 0;
  GLuint f = compile(GL_FRAGMENT_SHADER, fs, err);
  if (!f) { DeleteShader(v); return 0; }
  GLuint p = CreateProgram();
  AttachShader(p, v);
  AttachShader(p, f);
  LinkProgram(p);
  DeleteShader(v);
  DeleteShader(f);
  GLint ok = 0;
  GetProgramiv(p, GL_LINK_STATUS, &ok);
  if (!ok) {
    char log[2048];
    GetProgramInfoLog(p, sizeof log, nullptr, log);
    if (err) *err = std::string("link: ") + log;
    DeleteProgram(p);
    return 0;
  }
  return p;
}

}  // namespace ds::gl
