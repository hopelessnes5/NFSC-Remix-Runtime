// Fork-owned. Rain map, step 2: relief of the traced height field. Per texel the depression (how much lower it
// is than the ground around it, which is where water pools), the slope (where water runs off) and the rain cover,
// blurred over the feather radius with a tent filter so cover edges come out as a smooth gradient instead of a
// texel-hard line. Neighbours more than a meter away in height are not ground next to this texel (walls,
// bridges) and are left out of the relief.

#include "rtx/pass/common_bindings.slangh"
#include "rtx/pass/fork_rain_map/rain_map_bindings.slangh"
#include "rtx/pass/raytrace_args.h"

#include "rtx/utility/math.slangh"

static const float kMissBelow = 0.5f;      // heights this far below the trace bottom are misses
static const float kNeighbourRange = 1.0f; // meters; beyond that a neighbour is not the same ground

float2 loadTexel(int2 texel)
{
  const int last = int(cb.wetMapResolution) - 1;
  return RainMapHeightInput[clamp(texel, int2(0, 0), int2(last, last))];
}

// Ground height of a texel; false where the trace found nothing
bool loadHeight(int2 texel, out float height)
{
  height = loadTexel(texel).x;
  return height > cb.wetMapTraceBottom - kMissBelow;
}

// 1 when the texel's cover stands at least the rain shadow min height above its own ground, -1 where the trace
// found nothing (left out of the blur), 0 otherwise
float loadCovered(int2 texel)
{
  const float2 value = loadTexel(texel);
  if (value.x <= cb.wetMapTraceBottom - kMissBelow)
  {
    return -1.0f;
  }
  return value.y - value.x >= cb.wetOcclusionMinHeight ? 1.0f : 0.0f;
}

[shader("compute")]
[numthreads(8, 8, 1)]
void main(uint2 threadId : SV_DispatchThreadID)
{
  if (any(threadId >= cb.wetMapResolution))
  {
    return;
  }

  const float2 own = loadTexel(int2(threadId));
  const float height = own.x;
  if (height <= cb.wetMapTraceBottom - kMissBelow)
  {
    RainMapOutput[threadId] = float4(cb.wetMapTraceBottom - 1.0f, cb.wetMapTraceBottom - 1.0f, 0.0f, 0.0f);
    return;
  }

  // The inner ring is enough for local slope and basin shape.
  const int r1 = max(1, int(round(1.5f / cb.wetMapTexel)));
  const int d1 = max(1, int(round(float(r1) * 0.7071f)));
  const int2 offsets[8] = {
    int2(r1, 0), int2(-r1, 0), int2(0, r1), int2(0, -r1),
    int2(d1, d1), int2(-d1, d1), int2(d1, -d1), int2(-d1, -d1)
  };

  // Fit a plane to the inner ring with centered coordinates. Missing samples and height
  // rejection make the surviving ring asymmetric, so its cross term cannot be assumed zero.
  float sumX = 0.0f, sumY = 0.0f, sumH = 0.0f;
  float sumXX = 0.0f, sumYY = 0.0f, sumXY = 0.0f;
  float sumXH = 0.0f, sumYH = 0.0f;
  float sampleCount = 0.0f;
  float innerHeights[8];
  bool innerValid[8];
  [unroll]
  for (int i = 0; i < 8; ++i)
  {
    innerValid[i] = false;
  }
  [unroll]
  for (int i = 0; i < 8; ++i)
  {
    float neighbour;
    if (loadHeight(int2(threadId) + offsets[i], neighbour) && abs(neighbour - height) < kNeighbourRange)
    {
      const vec2 d = vec2(offsets[i]) * cb.wetMapTexel;
      const float dh = neighbour - height;
      innerHeights[i] = dh;
      innerValid[i] = true;
      sumX += d.x;
      sumY += d.y;
      sumH += dh;
      sumXX += d.x * d.x;
      sumYY += d.y * d.y;
      sumXY += d.x * d.y;
      sumXH += d.x * dh;
      sumYH += d.y * dh;
      sampleCount += 1.0f;
    }
  }

  float gx = 0.0f;
  float gy = 0.0f;
  float depression = 0.0f;
  if (sampleCount >= 3.0f)
  {
    const float invCount = 1.0f / sampleCount;
    const float meanX = sumX * invCount;
    const float meanY = sumY * invCount;
    const float meanH = sumH * invCount;
    const float cxx = sumXX - sumX * meanX;
    const float cyy = sumYY - sumY * meanY;
    const float cxy = sumXY - sumX * meanY;
    const float cxh = sumXH - sumX * meanH;
    const float cyh = sumYH - sumY * meanH;
    const float determinant = cxx * cyy - cxy * cxy;
    if (determinant > 1e-6f)
    {
      gx = (cxh * cyy - cyh * cxy) / determinant;
      gy = (cyh * cxx - cxh * cxy) / determinant;
    }

    // A real basin has higher ground on both sides of at least one axis. Taking the
    // weaker member of each opposite pair rejects a one-sided curb step while retaining
    // a long channel (high on both banks, flat along its length) and closed basins.
    float pairRise = 0.0f;
    const int pairA[4] = { 0, 2, 4, 6 };
    const int pairB[4] = { 1, 3, 7, 5 };
    [unroll]
    for (int i = 0; i < 4; ++i)
    {
      const int a = pairA[i];
      const int b = pairB[i];
      if (innerValid[a] && innerValid[b])
      {
        const float riseA = max(innerHeights[a], 0.0f);
        const float riseB = max(innerHeights[b], 0.0f);
        pairRise = max(pairRise, min(riseA, riseB));
      }
    }
    // Requiring both sides of an axis to rise rejects a one-sided curb step while
    // retaining a channel between its banks and a closed basin on a sloped plane.
    depression = pairRise;
  }

  // Rain cover blurred with a tent over the feather radius
  const int radius = clamp(int(round(cb.wetOcclusionFeather / cb.wetMapTexel)), 0, 12);
  float coverSum = 0.0f;
  float coverWeight = 0.0f;
  for (int dy = -radius; dy <= radius; ++dy)
  {
    for (int dx = -radius; dx <= radius; ++dx)
    {
      const float covered = loadCovered(int2(threadId) + int2(dx, dy));
      if (covered >= 0.0f)
      {
        const float weight = float((radius + 1 - abs(dx)) * (radius + 1 - abs(dy)));
        coverSum += covered * weight;
        coverWeight += weight;
      }
    }
  }
  const float coverage = coverWeight > 0.0f ? coverSum / coverWeight : 0.0f;

  RainMapOutput[threadId] = float4(coverage, height, depression, length(vec2(gx, gy)));
}
