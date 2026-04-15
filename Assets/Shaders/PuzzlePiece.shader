Shader "Custom/PuzzlePiece"
{
    Properties
    {
        [PerRendererData] _MainTex ("Sprite Texture", 2D) = "white" {}
        _Color ("Tint", Color) = (1,1,1,1)

        // --- SDF 基础属性 ---
        _CornerRadius ("Corner Radius", Range(0, 0.5)) = 0.1

        // --- 双描边属性 ---
        _OuterOutlineWidth ("Outer Stroke Width", Range(0, 0.05)) = 0.005
        _OuterOutlineColor ("Outer Stroke Color", Color) = (0,0,0,1)

        _InnerOutlineWidth ("Inner Stroke Width", Range(0, 0.1)) = 0.015
        _InnerOutlineColor ("Inner Stroke Color", Color) = (1,1,1,1)

        // --- 连接状态 ---
        _ConnectedState ("Connected State (T,R,B,L)", Vector) = (0, 0, 0, 0)

        // --- 网格切图属性 ---
        _NumCols ("Grid Columns", Float) = 3
        _NumRows ("Grid Rows", Float) = 3
        _CellIndex ("Current Index (1-based)", Float) = 1

        // 边缘缩进
        _EdgeShrink ("Edge Shrink", Range(0, 0.01)) = 0.003

        // --- UI 标准属性 ---
        _StencilComp ("Stencil Comparison", Float) = 8
        _Stencil ("Stencil ID", Float) = 0
        _StencilOp ("Stencil Operation", Float) = 0
        _StencilWriteMask ("Stencil Write Mask", Float) = 255
        _StencilReadMask ("Stencil Read Mask", Float) = 255
        _ColorMask ("Color Mask", Float) = 15
        [Toggle(UNITY_UI_ALPHACLIP)] _UseUIAlphaClip ("Use Alpha Clip", Float) = 0
    }

    SubShader
    {
        Tags
        {
            "Queue"="Transparent"
            "IgnoreProjector"="True"
            "RenderType"="Transparent"
            "PreviewType"="Plane"
            "CanUseSpriteAtlas"="True"
        }

        Stencil
        {
            Ref [_Stencil]
            Comp [_StencilComp]
            Pass [_StencilOp]
            ReadMask [_StencilReadMask]
            WriteMask [_StencilWriteMask]
        }

        Cull Off
        Lighting Off
        ZWrite Off
        ZTest [unity_GUIZTestMode]
        Blend SrcAlpha OneMinusSrcAlpha
        ColorMask [_ColorMask]

        Pass
        {
            Name "Default"
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma target 3.0

            #include "UnityCG.cginc"
            #include "UnityUI.cginc"

            #pragma multi_compile_local _ UNITY_UI_CLIP_RECT
            #pragma multi_compile_local _ UNITY_UI_ALPHACLIP

            struct appdata_t
            {
                float4 vertex   : POSITION;
                float4 color    : COLOR;
                float2 uv       : TEXCOORD0;
            };

            struct v2f
            {
                float4 vertex   : SV_POSITION;
                fixed4 color    : COLOR;
                float2 uv       : TEXCOORD0;
                float4 worldPosition : TEXCOORD1;
            };

            // 保持内存对齐的好习惯（防患未然）
            sampler2D _MainTex;
            fixed4 _Color;
            fixed4 _OuterOutlineColor;
            fixed4 _InnerOutlineColor;
            fixed4 _TextureSampleAdd;
            float4 _ClipRect;
            float4 _ConnectedState;

            float _CornerRadius;
            float _OuterOutlineWidth;
            float _InnerOutlineWidth;
            float _NumCols;
            float _NumRows;
            float _CellIndex;
            float _EdgeShrink;

            v2f vert(appdata_t v)
            {
                v2f OUT;
                OUT.worldPosition = v.vertex;
                OUT.vertex = UnityObjectToClipPos(OUT.worldPosition);
                OUT.uv = v.uv;
                OUT.color = v.color * _Color;
                return OUT;
            }

            float sdRoundedBoxIndependent(float2 p, float2 b, float4 r)
            {
                float2 r_side = (p.x > 0.0) ? r.xy : r.zw;
                float r_current = (p.y > 0.0) ? r_side.x : r_side.y;
                float2 q = abs(p) - b + r_current;
                return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - r_current;
            }

            fixed4 frag(v2f IN) : SV_Target
            {
                float isTop    = _ConnectedState.x;
                float isRight  = _ConnectedState.y;
                float isBottom = _ConnectedState.z;
                float isLeft   = _ConnectedState.w;

                // ==============================
                // 0. 自适应长宽比修正
                // ==============================
                float rateX = length(float2(ddx(IN.uv.x), ddy(IN.uv.x)));
                float rateY = length(float2(ddx(IN.uv.y), ddy(IN.uv.y)));
                float scaleY = (rateY > 1e-6) ? (rateX / rateY) : 1.0;

                float2 scaleSpace = float2(1.0, scaleY);
                float2 uv_centered_scaled = (IN.uv - 0.5) * scaleSpace;

                // ==============================
                // 1. [双重坐标系统准备]
                // ==============================
                float maskShrinkTop    = (isTop > 0.5)    ? 0.0 : _EdgeShrink;
                float maskShrinkRight  = (isRight > 0.5)  ? 0.0 : _EdgeShrink;
                float maskShrinkBottom = (isBottom > 0.5) ? 0.0 : _EdgeShrink;
                float maskShrinkLeft   = (isLeft > 0.5)   ? 0.0 : _EdgeShrink;

                float2 baseSize = float2(1.0, 1.0) * scaleSpace;
                float2 maskSize = baseSize - float2(maskShrinkLeft + maskShrinkRight, maskShrinkBottom + maskShrinkTop);
                float2 maskHalfSize = maskSize * 0.5;
                float2 maskCenterOffset = float2((maskShrinkLeft - maskShrinkRight) * 0.5, (maskShrinkBottom - maskShrinkTop) * 0.5);
                float2 mask_uv_centered = uv_centered_scaled - maskCenterOffset;

                float expandTop    = (isTop > 0.5)    ? _OuterOutlineWidth : 0.0;
                float expandRight  = (isRight > 0.5)  ? _OuterOutlineWidth : 0.0;
                float expandBottom = (isBottom > 0.5) ? _OuterOutlineWidth : 0.0;
                float expandLeft   = (isLeft > 0.5)   ? _OuterOutlineWidth : 0.0;

                float2 sdfSize = maskSize + float2(expandLeft + expandRight, expandBottom + expandTop);
                float2 sdfHalfSize = sdfSize * 0.5;
                float2 sdfCenterOffset = maskCenterOffset + float2((expandRight - expandLeft) * 0.5, (expandTop - expandBottom) * 0.5);
                float2 sdf_uv_centered = uv_centered_scaled - sdfCenterOffset;

                // ==============================
                // 2. [SDF 计算]
                // ==============================
                float r_TR = (isTop > 0.5 || isRight > 0.5) ? 0.0 : _CornerRadius;
                float r_BR = (isBottom > 0.5 || isRight > 0.5) ? 0.0 : _CornerRadius;
                float r_TL = (isTop > 0.5 || isLeft > 0.5) ? 0.0 : _CornerRadius;
                float r_BL = (isBottom > 0.5 || isLeft > 0.5) ? 0.0 : _CornerRadius;
                float4 radii = float4(r_TR, r_BR, r_TL, r_BL);

                float dist = sdRoundedBoxIndependent(sdf_uv_centered, sdfHalfSize, radii);
                float delta = fwidth(dist);

                // 【修复点】：使用 saturate 确保形状 Alpha 不超标
                float shapeAlpha = saturate(1.0 - smoothstep(0.0 - delta, 0.0 + delta, dist));

                float totalWidth = _OuterOutlineWidth + _InnerOutlineWidth;
                float innerStrokeFactor = smoothstep(-totalWidth - delta, -totalWidth + delta, dist);
                float outerStrokeFactor = smoothstep(-_OuterOutlineWidth - delta, -_OuterOutlineWidth + delta, dist);

                // ==============================
                // 3. [遮罩逻辑]
                // ==============================
                float mask = 1.0;
                float epsilon = delta * 1.5;
                float2 cutThreshold = maskHalfSize - totalWidth - epsilon;
                float2 cornerZone = maskHalfSize - totalWidth;

                if (isTop > 0.5 && mask_uv_centered.y > cutThreshold.y) {
                    bool preserveRight = (isRight < 0.5) && (mask_uv_centered.x > cornerZone.x);
                    bool preserveLeft  = (isLeft < 0.5)  && (mask_uv_centered.x < -cornerZone.x);
                    if (!preserveRight && !preserveLeft) mask = 0.0;
                }
                if (isRight > 0.5 && mask_uv_centered.x > cutThreshold.x) {
                    bool preserveTop    = (isTop < 0.5)    && (mask_uv_centered.y > cornerZone.y);
                    bool preserveBottom = (isBottom < 0.5) && (mask_uv_centered.y < -cornerZone.y);
                    if (!preserveTop && !preserveBottom) mask = 0.0;
                }
                if (isBottom > 0.5 && mask_uv_centered.y < -cutThreshold.y) {
                    bool preserveRight = (isRight < 0.5) && (mask_uv_centered.x > cornerZone.x);
                    bool preserveLeft  = (isLeft < 0.5)  && (mask_uv_centered.x < -cornerZone.x);
                    if (!preserveRight && !preserveLeft) mask = 0.0;
                }
                if (isLeft > 0.5 && mask_uv_centered.x < -cutThreshold.x) {
                    bool preserveTop    = (isTop < 0.5)    && (mask_uv_centered.y > cornerZone.y);
                    bool preserveBottom = (isBottom < 0.5) && (mask_uv_centered.y < -cornerZone.y);
                    if (!preserveTop && !preserveBottom) mask = 0.0;
                }

                innerStrokeFactor *= mask;
                outerStrokeFactor *= mask;

                // ==============================
                // 4. [纹理采样] (修复版：解决 AMD/Exynos 等 GPU 浮点异常及 fmod 越界问题)
                // ==============================
                // 强制将外部参数对齐到绝对的整数，抹平 2.9999 或 3.0001 的微小误差
                float cols = round(_NumCols);
                float rows = round(_NumRows);
                float index = round(_CellIndex);

                float totalCells = cols * rows;
                float safeIndex = clamp(index, 1.0, totalCells);
                
                // 基于 0 的索引
                float mathIndex = safeIndex - 1.0; 

                // 安全计算行号 (加上 0.1 避免 3.0/3.0=0.9999 被 floor 砍成 0)
                float rowIndex = floor((mathIndex + 0.1) / cols);

                // 绝对安全的求余运算，替代 fmod！
                // 整数相减不会出现底层架构对 fmod(x,x) 的错误判断边界
                float colIndex = mathIndex - rowIndex * cols;

                // 计算 UV 的基础大小
                float2 cellSize = float2(1.0 / cols, 1.0 / rows);
                float targetRow = (rows - 1.0) - rowIndex;

                float2 gridUV;
                gridUV.x = (IN.uv.x + colIndex) * cellSize.x;
                gridUV.y = (IN.uv.y + targetRow) * cellSize.y;
                
                half4 texColor = (tex2D(_MainTex, gridUV) + _TextureSampleAdd) * IN.color;

                // ==============================
                // 5. [混合输出]
                // ==============================
                // 【核心修复点】：严格将混合的透明度限制在 0.0 到 1.0 之间
                float innerOpacity = saturate(innerStrokeFactor * _InnerOutlineColor.a);
                half3 rgbWithInner = lerp(texColor.rgb, _InnerOutlineColor.rgb, innerOpacity);

                float outerOpacity = saturate(outerStrokeFactor * _OuterOutlineColor.a);
                half3 finalRGB = lerp(rgbWithInner, _OuterOutlineColor.rgb, outerOpacity);

                half4 finalColor = half4(finalRGB, texColor.a * shapeAlpha);

                #ifdef UNITY_UI_CLIP_RECT
                finalColor.a *= UnityGet2DClipping(IN.worldPosition.xy, _ClipRect);
                #endif
                #ifdef UNITY_UI_ALPHACLIP
                clip (finalColor.a - 0.001);
                #endif

                return finalColor;
            }
            ENDCG
        }
    }
}
