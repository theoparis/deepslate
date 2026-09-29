#pragma once
// Minimal OpenGL 3.3 core loader: every entry point is resolved through SDL_GL_GetProcAddress,
// so nothing links against libGL directly. Functions live in namespace gl without the "gl" prefix.
#define GL_GLEXT_PROTOTYPES 1
#include <SDL3/SDL.h>
#include <SDL3/SDL_opengl.h>

#include <string>

namespace ds::gl {

#define DS_GL_FUNCS(X)                                                                                                        \
  X(GetString) X(GetError) X(GetIntegerv) X(Enable) X(Disable) X(BlendFunc) X(BlendFuncSeparate) X(DepthFunc) X(DepthMask)  \
  X(CullFace) X(FrontFace) X(ClearColor) X(Clear) X(Viewport) X(Scissor) X(LineWidth) X(PixelStorei) X(ReadPixels)            \
  X(GenTextures) X(DeleteTextures) X(BindTexture) X(TexParameteri) X(TexParameterf) X(TexImage2D) X(TexSubImage2D)             \
  X(TexImage3D) X(TexSubImage3D) X(GenerateMipmap) X(ActiveTexture) X(GenBuffers) X(DeleteBuffers) X(BindBuffer)              \
  X(BufferData) X(BufferSubData) X(GenVertexArrays) X(DeleteVertexArrays) X(BindVertexArray) X(EnableVertexAttribArray)       \
  X(VertexAttribPointer) X(DrawElements) X(DrawArrays) X(CreateShader) X(ShaderSource) X(CompileShader) X(GetShaderiv)        \
  X(GetShaderInfoLog) X(CreateProgram) X(AttachShader) X(LinkProgram) X(GetProgramiv) X(GetProgramInfoLog) X(UseProgram)       \
  X(DeleteShader) X(DeleteProgram) X(GetUniformLocation) X(Uniform1i) X(Uniform1f) X(Uniform2f) X(Uniform3f) X(Uniform4f)     \
  X(UniformMatrix4fv) X(BindAttribLocation) X(Finish) X(PolygonMode) X(ColorMask)

#define X(name) inline decltype(&::gl##name) name = nullptr;
DS_GL_FUNCS(X)
#undef X

// Returns false (and names the first missing function in `missing`) if loading failed.
bool load(std::string* missing);

GLuint make_program(const char* vs, const char* fs, std::string* err);

}  // namespace ds::gl
