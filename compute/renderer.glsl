#[compute]
#version 460

#define PI 3.1415926

layout(local_size_x = 4, local_size_y = 4, local_size_z = 1) in;

layout(set = 0, binding = 0, std430) restrict buffer CameraDataBuffer {
    mat4 camToWorld;
    mat4 invProjMat;
    float fov;
    float nearPlane;
    float farPlane;
}
cameraData;

layout(set = 0, binding = 6, std430) restrict buffer SettingsDataBuffer {
    int seed;
    int samples;
    int maxBounce;
    int iterations;
}
settings;

// Structs required in data transfer..

struct Material{
    vec3 albedo;
    float roughness;
    float emissionStr;
    float specularity;
};

struct Sphere{
    vec3 pos;
    float rad;
    float mat;
};

struct Plane{
    vec3 pos;
    vec3 norm;
    float mat;
};

struct Triangle{
    vec3 v0;
    vec3 v1;
    vec3 v2;
    float mat;
    vec3 n;
    float d;
};

layout(set = 0, binding = 1, std430) restrict buffer MaterialDataBuffer {
    Material data[];
}
matData;

layout(rgba8, binding = 2) restrict uniform image2D outputImage;

layout(set = 0, binding = 3, std430) restrict buffer PlaneDataBuffer {
    Plane data[];
}
planeData;

layout(set = 0, binding = 4, std430) restrict buffer SphereDataBuffer {
    Sphere data[];
}
sphereData;

layout(rgba16, binding = 5) restrict uniform image2D hdri;

layout(set = 0, binding = 7, std430) restrict buffer TriangleDataBuffer {
    Triangle data[];
}
triangleData;

// Structs

struct Ray{
    vec3 origin;
    vec3 dir;
};

struct Interdata{
    bool collided;
    vec3 colPoint;
    vec3 colNorm;
    float colDist;
    int matInd;
};

//xorshift random pseudo number generator-----
int xorshift(in int value) {
    value ^= value << 13;
    value ^= value >> 17;
    value ^= value << 5;
    return value;
}

float randomdd(inout int seed){
    int localIndex = int(gl_GlobalInvocationID.x+gl_GlobalInvocationID.y*gl_WorkGroupSize.x*gl_NumWorkGroups.x);
    seed = xorshift(seed * localIndex);
    seed = seed;
    return abs(fract(float(seed) / 4294967296.0));
}


uint TausStep(uint z, int S1, int S2, int S3, uint M)
{
    uint b = (((z << S1) ^ z) >> S2);
    return (((z & M) << S3) ^ b);    
}


int LCGStep(int z, int A, int C)
{
    return (A * z + C);    
}

float random(inout int seed){
    seed = int(TausStep(uint(seed), 13, 19, 12, 4294967294));
    int x = int(TausStep(uint(gl_GlobalInvocationID.x), 3, 11, 17, 4294967280));
    int y= int(TausStep(uint(gl_GlobalInvocationID.x), 2, 25, 4, 4294967288));
    int z = LCGStep(int(gl_GlobalInvocationID.y*gl_GlobalInvocationID.x), 1664525, 1013904223);


    return fract(2.3283064365387e-10 * (seed ^ x ^ y ^ z));
}



//random number generator end-------

Ray createRay(vec3 origin, vec3 dir){
    Ray ray;
    ray.origin = origin;
    ray.dir = dir;

    return ray;
}

Ray createCameraRay(vec2 uv){
    vec3 origin = (cameraData.camToWorld * vec4(0.0f, 0.0f, 0.0f, 1.0f)).xyz;
    vec3 direction = (cameraData.invProjMat * vec4(uv, 0.0f, 1.0f)).xyz;
    
    direction = (cameraData.camToWorld * vec4(direction, 0.0f)).xyz;
    direction = normalize(direction);

    return createRay(origin, direction);
}

Interdata intersectRay(Ray ray, Sphere s){
    Interdata id;

    vec3 l = s.pos - ray.origin;
    float dist = length(l);
    float tca = dot(ray.dir, l);

    if (tca < 0.0){
        id.collided = false;
        return id;
    }

    float d = dist*dist-tca*tca;

    if (d > s.rad*s.rad){
        id.collided = false;
        return id;
    }

    float thc = sqrt(s.rad*s.rad-d);
    float t = tca-thc;

    vec3 colPoint = ray.origin + ray.dir * t;
    vec3 colNorm = normalize(colPoint-s.pos);

    id.colDist = distance(ray.origin, colPoint);
    id.colPoint = colPoint;
    id.colNorm = colNorm;
    id.collided = true;
    id.matInd = int(s.mat);

    return id;
}

Interdata intersectRay(Ray ray, Plane p){
    Interdata colData;
    colData.collided = false;

    float rDotn = dot(ray.dir, p.norm);

    if (rDotn > 0){
        p.norm *= -1;
        rDotn *= -1;
    }
    
    if (abs(rDotn) < 0.0001){
      return colData;
    }
 
    float s = dot(p.norm, (p.pos - ray.origin)) / rDotn;
    
    if (s < 0){
        return colData;
    }
   
    vec3 colPoint = ray.origin + ray.dir * s;
    float dist = distance(ray.origin, colPoint);
    
    colData.colPoint = colPoint;
    colData.colNorm = p.norm;
    colData.colDist = dist;
    colData.matInd = int(p.mat);
    colData.collided = true;

    return colData;
}

Interdata intersectRay(Ray ray, Triangle tr){
    Interdata colData;
    colData.collided = false;

    float nDotDir = dot(tr.n, ray.dir);
    vec3 norm = tr.n;
    float d = tr.d;
    float mult = 1;

    if (nDotDir > 0){
        nDotDir *= -1;
        norm *= -1;
        d *= -1;
        mult = -1;
    }

    if (nDotDir == 0.0){
        return colData;
    }

    float t = -(dot(norm, ray.origin) + d) / nDotDir;

    if (t < 0){
        return colData;
    }

    vec3 p = ray.origin + t*ray.dir;

    vec3 edge0 = (tr.v1 - tr.v0)*mult;
    vec3 edge1 = (tr.v2 - tr.v1)*mult;
    vec3 edge2 = (tr.v0 - tr.v2)*mult;
    vec3 C0 = p - tr.v0;
    vec3 C1 = p - tr.v1;
    vec3 C2 = p - tr.v2;
    if (!(dot(norm, cross(edge0, C0)) > 0.0 && dot(norm, cross(edge1, C1)) > 0.0 && dot(norm, cross(edge2, C2)) > 0.0)){
        return colData;
    }

    colData.colPoint = p;
    colData.colNorm = norm;
    colData.colDist = t;
    colData.matInd = int(tr.mat);
    colData.collided = true;

    return colData;
}

Interdata checkIntersection(Ray ray){
    Interdata toReturn;
    toReturn.collided = false;
    float minColDist = 100000000.0;

    for (int i=0; i<sphereData.data.length(); i++){
        Interdata colData = intersectRay(ray, sphereData.data[i]);

        if (colData.collided && colData.colDist < minColDist){
            minColDist = colData.colDist;
            toReturn = colData;
        }
    }

    for (int i=0; i<planeData.data.length(); i++){
        Interdata colData = intersectRay(ray, planeData.data[i]);

        if (colData.collided && colData.colDist < minColDist){
            minColDist = colData.colDist;
            toReturn = colData;
        }
    }

    for (int i=0; i<triangleData.data.length(); i++){
        Interdata colData = intersectRay(ray, triangleData.data[i]);

        if (colData.collided && colData.colDist < minColDist){
            minColDist = colData.colDist;
            toReturn = colData;
        }
    }

    return toReturn;
}

vec3 getEmission(in Interdata data){
    return matData.data[data.matInd].emissionStr * matData.data[data.matInd].albedo;
}

vec3 getAlbedo(in Interdata data){
    return matData.data[data.matInd].albedo;
}

float getRoughness(in Interdata data){
    return matData.data[data.matInd].roughness;
}

float getSpecularity(in Interdata data){
    return matData.data[data.matInd].specularity;
}

vec3 getRandomHemiDir(){
    float u = random(settings.seed) * 2.0 - 1.0;
    float theta = random(settings.seed) * 2.0 * PI;
    float uMult = sqrt(1.0-u*u);

    return vec3(uMult*cos(theta), u, uMult*sin(theta));
}

vec3 getSkyColour(vec3 dir){
    const ivec2 hdriDim = imageSize(hdri);
    int u = int(hdriDim.x*(0.5 + atan(dir.z, -dir.x)/(2*PI)));
    int v = int(hdriDim.y*(0.5 + asin(-dir.y)/PI));
    
    return imageLoad(hdri, ivec2(u, v)).xyz;
}

vec3 randDir(vec3 origin, vec3 dir){
    vec3 a = cross(dir, vec3(1, 0, 0));
    vec3 b = cross(a, dir);
    if (length(a) == 0){
        a = vec3(0, 1, 0);
        b = vec3(0, 0, 1);
    }

    mat3 transMat = mat3(a, dir, b);
    mat3 invTrans = inverse(transMat);

    const float height = 100.0;
    float theta = random(settings.seed)*2.0*PI;
    float phi = random(settings.seed)*PI/1500.0;
    float rad = height * tan(phi);

    vec3 pointLoc = vec3(cos(theta)*rad, height, sin(theta)*rad);
    vec3 globalPointLoc = pointLoc*invTrans;

    vec3 result = normalize(globalPointLoc-origin);
    return result;
}

void gammaCorrect(inout vec3 col){
    col = vec3(pow(col.x, 1/2.2), pow(col.y, 1/2.2), pow(col.z, 1/2.2));
}

void main(){
    const ivec2 texSize = ivec2(gl_WorkGroupSize.xy) * ivec2(gl_NumWorkGroups.xy);
    const ivec2 coord = ivec2(gl_GlobalInvocationID.xy);
    const vec2 uv = vec2(float(coord.x) / float(texSize.x) - 0.5, float(coord.y) / float(texSize.y) - 0.5) * vec2(2.0, 2.0);

    Ray camRay = createCameraRay(uv);
    camRay.dir = randDir(camRay.origin, camRay.dir);
    Ray ray = createRay(camRay.origin, camRay.dir);

    vec3 col = vec3(0.0, 0.0, 0.0);
    vec3 prevPixel = imageLoad(outputImage, coord).rgb;
    vec4 pixelVal;

    float skyStr = 0.0;

    vec3 newOrigin;
    vec3 bounceDir;
    vec3 perfectDir;
    float nDot;
    vec3 diff = vec3(1.0, 1.0, 1.0);

    //TODO: pathtracing, multiple iterations for some reason returns vague results so fix it later
    for (int k=0; k<1; k++){
        for (int i=0; i<settings.maxBounce; i++){
            Interdata colData = checkIntersection(ray);
            if (colData.collided){
                newOrigin = colData.colPoint + colData.colNorm * 0.00001;

                bounceDir = normalize(colData.colNorm + getRandomHemiDir());
                perfectDir = reflect(ray.dir, colData.colNorm);
                bool specularBounce = random(settings.seed) < getSpecularity(colData);
                
                nDot = dot(bounceDir, colData.colNorm);
                if (nDot < 0.0){
                    nDot *= -1.0;
                    bounceDir *= -1.0;
                }

                ray.origin = newOrigin;
                ray.dir = mix(bounceDir, perfectDir, (1.0-getRoughness(colData)) * ((specularBounce)?1:0));

                col += getEmission(colData)*diff;
                diff *= mix(getAlbedo(colData), vec3(1.0, 1.0, 1.0), ((specularBounce)?1:0));
            }
            else{
                col += diff*getSkyColour(ray.dir)*skyStr;
                break;
            }
        

            vec3 newPixel = col.xyz;
            //newPixel = vec3(min(newPixel.x, 1.0), min(newPixel.y, 1.0), min(newPixel.z, 1.0));
            gammaCorrect(newPixel);

            //pixelVal = vec4((prevPixel * (float(settings.samples*settings.iterations+k-1.0)/float(settings.samples*settings.iterations+k)) + newPixel/float(settings.samples*settings.iterations+k)).xyz, 1.0);
            pixelVal = vec4((prevPixel * (float(settings.samples-1.0)/float(settings.samples)) + newPixel/float(settings.samples)).xyz, 1.0);

            /*prevPixel = pixelVal.xyz;
            //prevPixel = vec3(min(prevPixel.x, 1.0), min(prevPixel.y, 1.0), min(prevPixel.z, 1.0));
            ray = createRay(camRay.origin, camRay.dir);
            col = vec3(0.0, 0.0, 0.0);
            diff = vec3(1.0, 1.0, 1.0);*/
        }
    }

    imageStore(outputImage, coord, pixelVal);
} 