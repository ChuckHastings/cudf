# Copyright (c) 2019, NVIDIA CORPORATION.
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# cython: profile=False
# distutils: language = c++
# cython: embedsignature = True
# cython: language_level = 3

from cugraph.cores.c_k_core cimport *
from cugraph.structure.c_graph cimport *
from cugraph.structure import graph_wrapper
from cugraph.utilities.column_utils cimport *
from libcpp cimport bool
from libc.stdint cimport uintptr_t
from libc.stdlib cimport calloc, malloc, free
from libc.float cimport FLT_MAX_EXP

import cudf
import cudf._lib as libcudf
import rmm
import numpy as np


def k_core(input_graph, k_core_graph, k, core_number):
    """
    Call gdf_k_core
    """
    cdef uintptr_t graph = graph_wrapper.allocate_cpp_graph()
    cdef gdf_graph * g = <gdf_graph*> graph

    if input_graph.adjlist:
        graph_wrapper.add_adj_list(graph, input_graph.adjlist.offsets, input_graph.adjlist.indices, input_graph.adjlist.weights)
    else:
        if input_graph.edgelist.weights:
            graph_wrapper.add_edge_list(graph, input_graph.edgelist.edgelist_df['src'], input_graph.edgelist.edgelist_df['dst'], input_graph.edgelist.edgelist_df['weights'])
        else:
            graph_wrapper.add_edge_list(graph, input_graph.edgelist.edgelist_df['src'], input_graph.edgelist.edgelist_df['dst'])
        err = gdf_add_adj_list(g)
        libcudf.cudf.check_gdf_error(err)
        offsets, indices, values = graph_wrapper.get_adj_list(graph)
        input_graph.adjlist = input_graph.AdjList(offsets, indices, values)

    cdef uintptr_t rGraph = graph_wrapper.allocate_cpp_graph()
    cdef gdf_graph* rg = <gdf_graph*>rGraph

    cdef gdf_column c_vertex = get_gdf_column_view(core_number['vertex'])
    cdef gdf_column c_values = get_gdf_column_view(core_number['values'])
    err = gdf_k_core(g, k, &c_vertex, &c_values, rg)
    libcudf.cudf.check_gdf_error(err)

    if rg.edgeList is not NULL:
        df = cudf.DataFrame()
        df['src'], df['dst'], vals = graph_wrapper.get_edge_list(rGraph)
        if vals is not None:
            df['val'] = vals
        k_core_graph.add_edge_list(df)
    if rg.adjList is not NULL:
        off, ind, vals = graph_wrapper.get_adj_list(rGraph)
        k_core_graph.add_adj_list(off, ind, vals)
    if rg.transposedAdjList is not NULL:
        off, ind, vals = graph_wrapper.get_transposed_adj_list(rGraph)
        k_core_graph.add_transposed_adj_list(off, ind, vals)
