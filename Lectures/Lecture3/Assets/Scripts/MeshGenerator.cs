using System;
using System.Collections.Generic;
using System.Linq;
using UnityEngine;

[RequireComponent(typeof(MeshFilter))]
public class MeshGenerator : MonoBehaviour
{
    public MetaBallField Field = new MetaBallField();

    private MeshFilter _filter;
    private Mesh _mesh;

    private List<Vector3> vertices = new List<Vector3>();
    private List<Vector3> normals = new List<Vector3>();
    private List<int> indices = new List<int>();

    /// <summary>
    /// Executed by Unity upon object initialization. <see cref="https://docs.unity3d.com/Manual/ExecutionOrder.html"/>
    /// </summary>
    private void Awake()
    {
        // Getting a component, responsible for storing the mesh
        _filter = GetComponent<MeshFilter>();

        // instantiating the mesh
        _mesh = _filter.mesh = new Mesh();

        // Just a little optimization, telling unity that the mesh is going to be updated frequently
        _mesh.MarkDynamic();
    }

    /// <summary>
    /// Executed by Unity on every frame <see cref="https://docs.unity3d.com/Manual/ExecutionOrder.html"/>
    /// You can use it to animate something in runtime.
    /// </summary>
    private void Update()
    {
        vertices.Clear();
        indices.Clear();
        normals.Clear();

        Field.Update();
        // ----------------------------------------------------------------
        // Generate mesh here. Below is a sample code of a cube generation.
        // ----------------------------------------------------------------

        const float step = 0.1f;

        for (var x = Field.MinX() - step; x < Field.MaxX() + step; x += step)
        {
            for (var y = Field.MinY() - step; y < Field.MaxY() + step; y += step)
            {
                for (var z = Field.MinZ() - step; z < Field.MaxZ() + step; z += step)
                {
                    CreateSurfaceInsideCube(new Vector3(x, y, z), step);
                }
            }
        }


        var eps = 1e-4f;
        var dx = new Vector3(eps, 0, 0);
        var dy = new Vector3(0, eps, 0);
        var dz = new Vector3(0, 0, eps);

        normals = vertices.Select(vertex => -Vector3.Normalize(new Vector3(
            Field.F(vertex + dx) - Field.F(vertex - dx),
            Field.F(vertex + dy) - Field.F(vertex - dy),
            Field.F(vertex + dz) - Field.F(vertex - dz)
        ))).ToList();

        // Here unity automatically assumes that vertices are points and hence (x, y, z) will be represented as (x, y, z, 1) in homogenous coordinates
        _mesh.Clear();
        _mesh.SetVertices(vertices);
        _mesh.SetTriangles(indices, 0);
        _mesh.SetNormals(normals);

        // Upload mesh data to the GPU
        _mesh.UploadMeshData(false);
    }

    private void CreateSurfaceInsideCube(Vector3 cubeVertex, float size)
    {
        var cubeVertices = MarchingCubes.Tables._cubeVertices.Select(d => cubeVertex + size * d).ToList();

        var fValues = cubeVertices.Select(vertex => Field.F(vertex)).ToList();
        var mask = 0;
        for (var i = 0; i < fValues.Count; i++)
        {
            var flag = fValues[i] > 0 ? 1 : 0;
            mask |= flag << i;
        }

        var surface = new SurfaceInsideCube(vertices, indices);
        var trianglesNumber = MarchingCubes.Tables.CaseToTrianglesCount[mask];
        for (var i = 0; i < trianglesNumber; i++)
        {
            var edges = MarchingCubes.Tables.CaseToVertices[mask][i];
            var edgesList = new List<int> {edges.x, edges.y, edges.z};
            surface.AddTriangle();
            foreach (var edge in edgesList)
            {
                var cubeEdge = MarchingCubes.Tables._cubeEdges[edge];
                var ia = cubeEdge[0];
                var ib = cubeEdge[1];
                var a = cubeVertices[ia];
                var b = cubeVertices[ib];
                var p = fValues[ib] / (fValues[ib] - fValues[ia]);
                var vertex = a * p + b * (1 - p);
                surface.AddVertex(vertex);
            }
        }
    }

    class SurfaceInsideCube
    {
        private readonly List<Vector3> _vertices;
        private readonly List<int> _indices;

        public SurfaceInsideCube(List<Vector3> vertices, List<int> indices)
        {
            _vertices = vertices;
            _indices = indices;
        }

        public void AddVertex(Vector3 vertex)
        {
            _vertices.Add(vertex);
        }

        public void AddTriangle()
        {
            _indices.Add(_vertices.Count);
            _indices.Add(_vertices.Count + 1);
            _indices.Add(_vertices.Count + 2);
        }
    }
}
