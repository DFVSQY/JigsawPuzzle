Shader "Custom/PuzzlePiece"
{
    Properties
    {
        [PerRendererData] _MainTex ("Sprite Texture", 2D) = "white" {}
        _Color ("Tint", Color) = (1,1,1,1)

        // --- SDF 基础属性 ---
        _CornerRadius ("Corner Radius", Range(0, 0.5)) = 0.1
        
        // --- 双描边属性 ---
        // 外描边 (细黑线)
        _OuterOutlineWidth ("Outer Stroke Width", Range(0, 0.05)) = 0.005 
        _OuterOutlineColor ("Outer Stroke Color", Color) = (0,0,0,1)
        
        // 内描边 (粗白线)
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
            #pragma target 2.0

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

            fixed4 _Color;
            sampler2D _MainTex;
            float4 _ClipRect;
            fixed4 _TextureSampleAdd;

            float _CornerRadius;
            float _OuterOutlineWidth;
            fixed4 _OuterOutlineColor;
            float _InnerOutlineWidth;
            fixed4 _InnerOutlineColor;
            float _NumCols;
            float _NumRows;
            float _CellIndex;
            float _EdgeShrink;
            float4 _ConnectedState;

            v2f vert(appdata_t v)
            {
                v2f OUT;
                OUT.worldPosition = v.vertex;
                OUT.vertex = UnityObjectToClipPos(OUT.worldPosition);
                OUT.uv = v.uv;
                OUT.color = v.color * _Color;
                return OUT;
            }

            // SDF 函数
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
                // 1. [双重坐标系统准备]
                // ==============================
                
                // --- 系统 A: Mask 坐标系 (用于遮罩/裁切) ---
                // 逻辑: 未连接时缩进(_EdgeShrink)，已连接时贴边(0.0)
                float maskShrinkTop    = (isTop > 0.5)    ? 0.0 : _EdgeShrink;
                float maskShrinkRight  = (isRight > 0.5)  ? 0.0 : _EdgeShrink;
                float maskShrinkBottom = (isBottom > 0.5) ? 0.0 : _EdgeShrink;
                float maskShrinkLeft   = (isLeft > 0.5)   ? 0.0 : _EdgeShrink;

                float2 maskSize = float2(1.0 - maskShrinkLeft - maskShrinkRight, 1.0 - maskShrinkBottom - maskShrinkTop);
                float2 maskHalfSize = maskSize * 0.5;
                float2 maskCenterOffset = float2((maskShrinkLeft - maskShrinkRight) * 0.5, (maskShrinkBottom - maskShrinkTop) * 0.5);
                float2 mask_uv_centered = IN.uv - 0.5 - maskCenterOffset;

                // --- 系统 B: SDF 坐标系 (用于绘制形状) ---
                // [关键修复]
                // 如果一边连上了，我们将 SDF 的形状向外"膨胀"一个外描边的宽度。
                // 这样，处于物理边缘的像素，就会落在 SDF 的"内描边(白)"区域，而不是"外描边(黑)"区域。
                // 从而消除了垂直方向的黑色封口。
                
                float expandTop    = (isTop > 0.5)    ? _OuterOutlineWidth : 0.0;
                float expandRight  = (isRight > 0.5)  ? _OuterOutlineWidth : 0.0;
                float expandBottom = (isBottom > 0.5) ? _OuterOutlineWidth : 0.0;
                float expandLeft   = (isLeft > 0.5)   ? _OuterOutlineWidth : 0.0;

                // SDF 的尺寸 = Mask尺寸 + 向外膨胀的量
                float2 sdfSize = maskSize + float2(expandLeft + expandRight, expandBottom + expandTop);
                float2 sdfHalfSize = sdfSize * 0.5;
                // SDF 的中心也需要相应偏移
                float2 sdfCenterOffset = maskCenterOffset + float2((expandRight - expandLeft) * 0.5, (expandTop - expandBottom) * 0.5);
                float2 sdf_uv_centered = IN.uv - 0.5 - sdfCenterOffset;

                // ==============================
                // 2. [SDF 计算] (使用膨胀后的坐标系)
                // ==============================
                float r_TR = (isTop > 0.5 || isRight > 0.5) ? 0.0 : _CornerRadius;
                float r_BR = (isBottom > 0.5 || isRight > 0.5) ? 0.0 : _CornerRadius;
                float r_TL = (isTop > 0.5 || isLeft > 0.5) ? 0.0 : _CornerRadius;
                float r_BL = (isBottom > 0.5 || isLeft > 0.5) ? 0.0 : _CornerRadius;
                float4 radii = float4(r_TR, r_BR, r_TL, r_BL);

                float dist = sdRoundedBoxIndependent(sdf_uv_centered, sdfHalfSize, radii);
                float delta = fwidth(dist);
                float shapeAlpha = 1.0 - smoothstep(0.0 - delta, 0.0 + delta, dist);

                float totalWidth = _OuterOutlineWidth + _InnerOutlineWidth;
                float innerStrokeFactor = smoothstep(-totalWidth - delta, -totalWidth + delta, dist);
                float outerStrokeFactor = smoothstep(-_OuterOutlineWidth - delta, -_OuterOutlineWidth + delta, dist);

                // ==============================
                // 3. [遮罩逻辑] (使用原始 Mask 坐标系)
                // ==============================
                // 注意：这里使用 maskHalfSize 和 mask_uv_centered
                float mask = 1.0;
                float epsilon = delta * 1.5;
                float2 cutThreshold = maskHalfSize - totalWidth - epsilon;
                float2 cornerZone = maskHalfSize - totalWidth; // 保护区阈值

                // [Top Mask]
                if (isTop > 0.5 && mask_uv_centered.y > cutThreshold.y)
                {
                    // 保护逻辑：如果邻边未连接，保留该角的垂直描边
                    bool preserveRight = (isRight < 0.5) && (mask_uv_centered.x > cornerZone.x);
                    bool preserveLeft  = (isLeft < 0.5)  && (mask_uv_centered.x < -cornerZone.x);
                    if (!preserveRight && !preserveLeft) mask = 0.0;
                }
                // [Right Mask]
                if (isRight > 0.5 && mask_uv_centered.x > cutThreshold.x)
                {
                    bool preserveTop    = (isTop < 0.5)    && (mask_uv_centered.y > cornerZone.y);
                    bool preserveBottom = (isBottom < 0.5) && (mask_uv_centered.y < -cornerZone.y);
                    if (!preserveTop && !preserveBottom) mask = 0.0;
                }
                // [Bottom Mask]
                if (isBottom > 0.5 && mask_uv_centered.y < -cutThreshold.y)
                {
                    bool preserveRight = (isRight < 0.5) && (mask_uv_centered.x > cornerZone.x);
                    bool preserveLeft  = (isLeft < 0.5)  && (mask_uv_centered.x < -cornerZone.x);
                    if (!preserveRight && !preserveLeft) mask = 0.0;
                }
                // [Left Mask]
                if (isLeft > 0.5 && mask_uv_centered.x < -cutThreshold.x)
                {
                    bool preserveTop    = (isTop < 0.5)    && (mask_uv_centered.y > cornerZone.y);
                    bool preserveBottom = (isBottom < 0.5) && (mask_uv_centered.y < -cornerZone.y);
                    if (!preserveTop && !preserveBottom) mask = 0.0;
                }

                innerStrokeFactor *= mask;
                outerStrokeFactor *= mask;

                // ==============================
                // 4. [纹理采样]
                // ==============================
                float totalCells = _NumCols * _NumRows;
                float safeIndex = clamp(_CellIndex, 1.0, totalCells);
                float mathIndex = floor(safeIndex - 1.0 + 0.1);
                float colIndex = fmod(mathIndex, _NumCols);
                float rowIndex = floor(mathIndex / _NumCols);
                float2 cellSize = float2(1.0 / _NumCols, 1.0 / _NumRows);
                float targetRow = (_NumRows - 1.0) - rowIndex;
                float2 gridUV;
                gridUV.x = (IN.uv.x + colIndex) * cellSize.x;
                gridUV.y = (IN.uv.y + targetRow) * cellSize.y;
                half4 texColor = (tex2D(_MainTex, gridUV) + _TextureSampleAdd) * IN.color;

                // ==============================
                // 5. [混合输出]
                // ==============================
                float innerOpacity = innerStrokeFactor * _InnerOutlineColor.a;
                half3 rgbWithInner = _InnerOutlineColor.rgb * innerOpacity + texColor.rgb * (1.0 - innerOpacity);
                float outerOpacity = outerStrokeFactor * _OuterOutlineColor.a;
                half3 finalRGB = _OuterOutlineColor.rgb * outerOpacity + rgbWithInner * (1.0 - outerOpacity);
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