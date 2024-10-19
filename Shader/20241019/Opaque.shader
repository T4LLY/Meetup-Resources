/*
MIT License

Copyright © 2024 T4LLY

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
*/

Shader "Particle/Opaque"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" {}
        _Tint("Tint color", Color) = (1, 1, 1, 1)
        _EdgeMin("Edge min", Range(0, 1)) = 0
        _EdgeMax("Edge max", Range(0, 1)) = 1
        _AlphaMultiplierScreenPosition("Alpha Multiplier for Screen Space Position", Float) = 1
        _AlphaMultiplierDepth("Alpha Multiplier for View Depth", Float) = 1
    }

    SubShader
    {
        LOD 100
        Cull Off

        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #include "UnityCG.cginc"

            struct appdata
            {
                float4 vertex : POSITION;
                float4 uv1 : TEXCOORD0;
                float4 uv2 : TEXCOORD1;
                float4 color : COLOR;
            };

            struct v2f
            {
                float2 uv : TEXCOORD0;
                float4 color : COLOR;
                float4 vertex : SV_POSITION;
                float4 screenPosition : TEXCOORD1;
                float4 headScreenPosition : TEXCOORD2;
                float alpha : TEXCOORD3;
                float distanceToCameraWS : TEXCOORD4;
                float distanceToCameraVS : TEXCOORD5;
            };

            sampler2D _MainTex;
            float4 _MainTex_ST;
            float3 _UdonHeadPos;
            float _EdgeMin;
            float _EdgeMax;
            float _AlphaMultiplierScreenPosition;
            float _AlphaMultiplierDepth;
            float4 _Tint;
            
            inline float sq(float x)
            {
                return x * x;
            }

            v2f vert (appdata v)
            {
                v2f o;
                o.uv = TRANSFORM_TEX(v.uv1.xy, _MainTex);
                o.color = v.color;

                float3 center = float3(v.uv1.zw, v.uv2.x);
                
                float3 worldPosition = mul(unity_ObjectToWorld, v.vertex).xyz;
                o.vertex = UnityObjectToClipPos(v.vertex);
                
                // 視線ベクトルを取得
                float3 viewDirWS = UnityWorldSpaceViewDir(worldPosition);

                // カメラまでの距離
                o.distanceToCameraWS = length(viewDirWS);
                
                float3 viewSpacePos = mul(UNITY_MATRIX_V, v.vertex).xyz;
                o.distanceToCameraVS = -viewSpacePos.z;
                
                // 視線方向に平面SDFを定義、0.3mオフセット
                o.alpha = saturate((dot(-normalize(viewDirWS), worldPosition - _UdonHeadPos) - 0.3) * 5);

                // パーティクル座標のスクリーンスペース座標を取得
                o.screenPosition = ComputeGrabScreenPos(o.vertex);
                
                // ターゲット頭部座標をスクリーンスペース座標に変換
                float4 headClipSpacePos = UnityObjectToClipPos(float4(_UdonHeadPos, 1));
                o.headScreenPosition = ComputeGrabScreenPos(headClipSpacePos);

                return o;
            }

            // http://extremelearning.com.au/unreasonable-effectiveness-of-quasirandom-sequences/
            float DitherPlastic(float2 pos)
            {
                return 2.0 * abs(frac(dot(pos, float2(0.75487767, 0.56984029))) - 0.5);
            }

            fixed4 frag (v2f i) : SV_Target
            {
                // 以下はvertに移したほうが効率のいい処理もあるので要最適化

                float2 particleUV = i.screenPosition.xy / i.screenPosition.w;
                float2 headUV = i.headScreenPosition.xy / i.headScreenPosition.w;

                // アスペクト比補正
                float aspectRatio = _ScreenParams.x / _ScreenParams.y;
                float2 correctedUV = float2((particleUV.x - headUV.x) * aspectRatio, particleUV.y - headUV.y);
                
                float alphaFromScreenPosition = length(correctedUV * i.distanceToCameraWS) * _AlphaMultiplierScreenPosition;

                float alphaFromDepth = smoothstep(0.2, 1, i.distanceToCameraVS * _AlphaMultiplierDepth);

                clip(smoothstep(_EdgeMin, _EdgeMax, saturate(max(alphaFromScreenPosition, i.alpha) * alphaFromDepth * i.color.a)) - DitherPlastic(_ScreenParams.xy * particleUV));

                return saturate(tex2D(_MainTex, i.uv) * i.color * _Tint);
            }
            ENDCG
        }
    }
    // Shadow Caster(必要) が書いてないので注意
}
