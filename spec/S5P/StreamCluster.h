#ifndef STREAM_CLUSTER_H
#define STREAM_CLUSTER_H

#include <vector>
#include <unordered_map>
#include "globalConfig.h"
#include "graph.h"
#include <stdexcept>
#include <limits>

class StreamCluster {
public:
    struct PairHash {
        template <class T1, class T2>
        std::size_t operator () (const std::pair<T1, T2>& p) const {
            auto h1 = std::hash<T1>{}(p.first);
            auto h2 = std::hash<T2>{}(p.second);
            return h1 ^ h2;
        }
    };
    std::vector<int> cluster;
    std::vector<int> cluster_S;     
    std::vector<int> cluster_B;     
    std::vector<int> degree;
    std::vector<int> degree_B;
    std::vector<int> degree_S;


    std::vector<int> volume;
    std::vector<int> volume_S;     
    std::vector<int> volume_B;     


    std::unordered_map<std::pair<int, int>, int, PairHash> innerAndCutEdge;

    Graph* graph;

    std::vector<int> clusterList;
    std::vector<int> clusterList_S;
    std::vector<int> clusterList_B;

    int maxVolume;
    int maxVolume_B;
    int maxVolume_S;
    std::string graphType;
    GlobalConfig config;


    StreamCluster();
    StreamCluster(Graph& graph, GlobalConfig& config);

    void setDegree(std::vector<int> degree);
    void setMaxVolume(int maxVolume);
    void setInnerAndCutEdge(std::unordered_map<int, std::unordered_map<int, int>> innerAndCutEdge);
    void startStreamCluster();
    void computeHybridInfo();
    void calculateDegree();
    int getEdgeNum(int cluster1, int cluster2);
    int getEdgeNum(int cluster1, int cluster2, std::string type);
    std::vector<int> getClusterList();
    std::vector<int> getCluster();
    std::vector<int> getDegree();
    int getClusterId(int id, std::string graphType);
    std::unordered_map<int, int> getVolume_S();
    std::unordered_map<int, std::unordered_map<int, int>> getInnerAndCutEdge();
    std::vector<int> getClusterList_B();
    std::vector<int> getClusterList_S();
    int getMaxVolume();
};

#endif // STREAM_CLUSTER_H
