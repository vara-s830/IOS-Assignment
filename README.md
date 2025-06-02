# IOS-Assignment

Challenge 2: Metal Shader Programming
1. Architecture Overview
MVVM: ViewModel manages camera feed and filter selection.

Metal: Custom compute, vertex, and fragment shaders.

Efficient GPU Resource Management: Texture caching, optimal formats.

2. Core Components
a. Compute Shaders (Image Processing)
Separable Gaussian Blur: Two-pass blur (horizontal, vertical).

Edge Detection: Sobel or Laplacian filter.

Basic Filters: Grayscale, invert, etc.

b. Vertex Shaders (Geometric Distortion)
Mesh Warp: Magnifying glass effect by displacing vertices.

Wave Distortion: Animate vertices with sine wave.

c. Fragment Shaders (Color Effects)
Chromatic Aberration: Offset RGB channels.

Tone Mapping: Custom mapping curve.

Film Grain & Vignette: Noise function + radial darkening.

d. GPU Memory Management
Use MTLPixelFormat.bgra8Unorm for camera textures.

Implement texture caching for repeated filters.

Minimize texture copies and use MTLHeap if needed.

3. Example ViewModel

4. 
