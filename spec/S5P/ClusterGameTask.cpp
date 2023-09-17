#include "ClusterGameTask.h"
#include "StreamCluster.h"
#include "ClusterPackGame.h"
#include "globalConfig.h"
#include <algorithm>


ClusterGameTask::ClusterGameTask(std::string graphType, int taskId, StreamCluster& sc, GlobalConfig& cfg)
    : graphType(graphType), config(&cfg), streamCluster(&sc), streamCluster_B(nullptr), streamCluster_S(nullptr){
    std::vector<int> clusterList = (graphType == "B" ? streamCluster->getClusterList_B() : streamCluster->getClusterList_S());
    int batchSize = config->batchSize;
    int begin = batchSize * taskId;
    int end = std::min(batchSize * (taskId + 1), static_cast<int>(clusterList.size()));
    this->cluster.assign(clusterList.begin() + begin, clusterList.begin() + end);
    this->config = config;
}

ClusterGameTask::ClusterGameTask(std::string graphType, StreamCluster& sc, int taskId_B, int taskId_S, GlobalConfig& cfg)
        : graphType(graphType), config(&cfg), streamCluster(&sc), streamCluster_B(nullptr), streamCluster_S(nullptr) {
    int batchSize = config->batchSize;
    int begin = batchSize * taskId_B;
    std::vector<int> clusterList_B = streamCluster->getClusterList_B();
    std::vector<int> clusterList_S = streamCluster->getClusterList_S();
    int end = std::min(batchSize * (taskId_B + 1), static_cast<int>(clusterList_B.size()));
    this->cluster_B.assign(clusterList_B.begin() + begin, clusterList_B.begin() + end);
    begin = batchSize * taskId_S;
    end = std::min(batchSize * (taskId_S + 1), static_cast<int>(clusterList_S.size()));
    this->cluster_S.assign(clusterList_S.begin() + begin, clusterList_S.begin() + end);
    this->config = config;
}


ClusterPackGame ClusterGameTask::call() {
    // std::cout << "hybrid cluster call" << std::endl;
    try {
        if (graphType == "hybrid") {
            ClusterPackGame clusterPackGame(streamCluster, cluster_B, cluster_S, graphType,config);
            clusterPackGame.initGameDouble();
            clusterPackGame.startGameDouble();
            return clusterPackGame;
        } else if (graphType == "B") {
            ClusterPackGame clusterPackGame(streamCluster, cluster, graphType,config);
            clusterPackGame.initGame();
            // clusterPackGame->startGame();
            return clusterPackGame;
        } else if (graphType == "S") {
            ClusterPackGame clusterPackGame(streamCluster, cluster, graphType,config);
            clusterPackGame.initGame();
            // clusterPackGame->startGame();
            return clusterPackGame;
        } else {
            std::cout << "graphType error" << std::endl;
        }
    } catch (const std::exception& e) {
        std::cerr << e.what() << std::endl;
    }
    ClusterPackGame tmp;
    return tmp;
}
