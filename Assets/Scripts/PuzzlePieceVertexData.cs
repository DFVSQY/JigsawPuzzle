using UnityEngine;
using UnityEngine.UI;

/// <summary>
/// 需要配合 PuzzlePieceVertexData 着色器使用，
/// 将需要的属性不同值数据注入到顶点数据中，主要是为了使用同一个材质，
/// 这样就可以合并DrawCall，优化性能了。
/// 注意：该脚本的父节点的Canvas需要开启 Additional Shader Channels中的 TexCoord1、TexCoord2
/// </summary>
[RequireComponent(typeof(RawImage))]
public class PuzzlePieceVertexData : BaseMeshEffect
{
    // --- 数据字段 ---
    [Header("Grid Info")]
    public float numCols = 3;
    public float numRows = 3;
    public float cellIndex = 1;

    [Header("Connection (1=Connected, 0=Open)")]
    public bool top;
    public bool right;
    public bool bottom;
    public bool left;

    // 初始化格子
    public void InitGrid(int cols, int rows, int index)
    {
        numCols = cols;
        numRows = rows;
        cellIndex = index;
        DirtyVertices();
    }

    // 设置连接状态
    public void SetConnection(bool t, bool r, bool b, bool l)
    {
        top = t;
        right = r;
        bottom = b;
        left = l;
        DirtyVertices();
    }

    private void DirtyVertices()
    {
        // 标记 graphic 需要重新生成 Mesh
        if (graphic != null)
        {
            graphic.SetVerticesDirty();
        }
    }

    // --- 核心重写方法 ---
    public override void ModifyMesh(VertexHelper vh)
    {
        if (!IsActive()) return;

        // 准备我们要注入的数据
        // UV1: x=Cols, y=Rows, z=Index
        Vector4 uv1Data = new Vector4(numCols, numRows, cellIndex, 0);

        // UV2: x=Top, y=Right, z=Bottom, w=Left
        Vector4 uv2Data = new Vector4(
            top ? 1f : 0f,
            right ? 1f : 0f,
            bottom ? 1f : 0f,
            left ? 1f : 0f
        );

        // 获取顶点列表
        var verts = new System.Collections.Generic.List<UIVertex>();
        vh.GetUIVertexStream(verts);

        // 遍历所有顶点，注入数据
        for (int i = 0; i < verts.Count; i++)
        {
            UIVertex v = verts[i];

            v.uv1 = uv1Data;
            v.uv2 = uv2Data;

            verts[i] = v;
        }

        // 应用回 VertexHelper
        vh.Clear();
        vh.AddUIVertexTriangleStream(verts);
    }
}