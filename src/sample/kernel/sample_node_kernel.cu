#include <stdio.h>
#include <stdlib.h>
#include <cassert>
#include <chrono>
#include <numeric>
#include <exception>

#include <cuda_runtime.h>
#include <curand_kernel.h>
#include <curand_mtgp32_host.h>
#include <curand_mtgp32dc_p_11213.h>

__global__ void sample_full_kernel(
                            int* outputSRC,
                            int* outputDST,
                            const int* graphEdge,
                            const int* boundList,
                            const int* trainNode,
                            int nodeNUM) {
    int idx = blockIdx.x * blockDim.x + threadIdx.x;
    for(int i = idx ; i < nodeNUM ; i += blockDim.x) {
        int writeIdx = i * 25;
        int id = trainNode[i];
        int idxStart = boundList[id];
        int idxEnd = boundList[id+1];
        for (int l = 0 ; l < (idxEnd - idxStart) ; l++) {
            outputSRC[writeIdx] = graphEdge[idxStart + l];
            outputDST[writeIdx++] = id;
        }

    }    
}

__global__ void sample1Hop(
                        int* outputSRC1,
                        int* outputDST1, 
                        const int* graphEdge,
                        const int* boundList,
                        const int* trainNode,
                        int sampleNUM1,
                        int nodeNUM,
                        unsigned long long seed
                            ) {
    int idx = blockIdx.x * blockDim.x + threadIdx.x;
    curandStateXORWOW_t state;
    curand_init(seed+idx,0,0,&state);
    unsigned int random_value = 0;
    int blockSize = sampleNUM1;
    for(int i = idx ; i < nodeNUM ; i += blockDim.x) {
        int writeIdx = i * blockSize;
        int id = trainNode[i];
        int idxStart = boundList[id];
        int idxEnd = boundList[id+1];
        int neirNUM = idxEnd - idxStart;
        for (int l = 0 ; l < neirNUM ; l++) { 
            random_value = curand(&state) % neirNUM;
            outputSRC1[writeIdx] = graphEdge[idxStart + random_value];
            outputDST1[writeIdx++] = id;
        }
        for (int l = neirNUM; l < sampleNUM1 ; l++) {
            outputSRC1[writeIdx] = 0;
            outputDST1[writeIdx++] = id;
        }
    }
}

__global__ void sample2Hop(
                        int* outputSRC1,
                        int* outputDST1,
                        int* outputSRC2,
                        int* outputDST2,
                        const int* graphEdge,
                        const int* boundList,
                        const int* trainNode,
                        int sampleNUM1,
                        int sampleNUM2,
                        int nodeNUM,
                        unsigned long long seed
                            ) {
    int idx = blockIdx.x * blockDim.x + threadIdx.x;
    curandStateXORWOW_t state;
    curand_init(seed+idx,0,0,&state);
    unsigned int random_value = 0;
    for(int i = idx ; i < nodeNUM ; i += blockDim.x) {
        int writeIdx = i * sampleNUM1;
        int id = trainNode[i];
        int idxStart = boundList[id];
        int idxEnd = boundList[id+1];
        int neirNUM = idxEnd - idxStart;
        for (int l = 0 ; l < neirNUM && l < sampleNUM1 ; l++) {
            random_value = curand(&state) % neirNUM;
            outputSRC1[writeIdx] = graphEdge[idxStart + random_value];
            outputDST1[writeIdx++] = id;
        }
        for (int l = neirNUM; l < sampleNUM1 ; l++) {
            outputSRC1[writeIdx] = -1;
            outputDST1[writeIdx++] = id;
        }

        // hop-2
        for (int l1 = 0 ; l1 < sampleNUM1 ; l1++) {
            // 二层采样id
            int l2_id = outputSRC1[i * sampleNUM1 + l1];
            if (l2_id > 0) {
                int l2_writeIdx = i*sampleNUM1*sampleNUM2 + l1*sampleNUM2;
                int l2_idStart = boundList[l2_id];
                int l2_idEnd = boundList[l2_id+1];
                int l2_neirNUM = l2_idEnd - l2_idStart;
                for (int l = 0 ; l < l2_neirNUM && l < sampleNUM2 ; l++) {
                    random_value = curand(&state) % l2_neirNUM;
                    outputSRC2[l2_writeIdx] = graphEdge[l2_idStart + random_value];
                    outputDST2[l2_writeIdx++] = l2_id;
                }
                for (int l = l2_neirNUM; l < sampleNUM2 ; l++) {
                    outputSRC2[l2_writeIdx] = -1;
                    outputDST2[l2_writeIdx++] = l2_id;
                }
            } else {
                int l2_writeIdx = i*sampleNUM1*sampleNUM2 + l1*sampleNUM2;
                for (int l = 0 ; l < sampleNUM2 ; l++) {
                    outputSRC2[l2_writeIdx] = -1;
                    outputDST2[l2_writeIdx++] = l2_id;
                }
            }
        }
    }
}

__global__ void sample3Hop(
                        int* outputSRC1,int* outputDST1,
                        int* outputSRC2,int* outputDST2,
                        int* outputSRC3,int* outputDST3,
                        const int* graphEdge,
                        const int* boundList,
                        const int* trainNode,
                        int sampleNUM1,int sampleNUM2,int sampleNUM3,
                        int nodeNUM,
                        unsigned long long seed
                            ) {
    int idx = blockIdx.x * blockDim.x + threadIdx.x;
    curandStateXORWOW_t state;
    curand_init(seed+idx,0,0,&state);
    unsigned int random_value = 0;
    for(int i = idx ; i < nodeNUM ; i += blockDim.x) {
        int writeIdx = i * sampleNUM1;
        int id = trainNode[i];
        int idxStart = boundList[id];
        int idxEnd = boundList[id+1];
        int neirNUM = idxEnd - idxStart;
        for (int l = 0 ; l < neirNUM && l < sampleNUM1 ; l++) {
            random_value = curand(&state) % neirNUM;
            outputSRC1[writeIdx] = graphEdge[idxStart + random_value];
            outputDST1[writeIdx++] = id;
        }
        for (int l = neirNUM; l < sampleNUM1 ; l++) {
            outputSRC1[writeIdx] = -1;
            outputDST1[writeIdx++] = id;
        }

        // hop-2
        for (int l1 = 0 ; l1 < sampleNUM1 ; l1++) {
            // 二层采样id
            int l2_id = outputSRC1[i * sampleNUM1 + l1];
            if (l2_id > 0) {
                int l2_writeIdx = i*sampleNUM1*sampleNUM2 + l1*sampleNUM2;
                int l2_idStart = boundList[l2_id];
                int l2_idEnd = boundList[l2_id+1];
                int l2_neirNUM = l2_idEnd - l2_idStart;
                for (int l = 0 ; l < l2_neirNUM && l < sampleNUM2 ; l++) {
                    random_value = curand(&state) % l2_neirNUM; 
                    outputSRC2[l2_writeIdx] = graphEdge[l2_idStart + random_value];
                    outputDST2[l2_writeIdx++] = l2_id;
                }
                for (int l = l2_neirNUM; l < sampleNUM2 ; l++) {
                    outputSRC2[l2_writeIdx] = -1;
                    outputDST2[l2_writeIdx++] = l2_id;
                }
            } else {
                int l2_writeIdx = i*sampleNUM1*sampleNUM2 + l1*sampleNUM2;
                for (int l = 0 ; l < sampleNUM2 ; l++) {
                    outputSRC2[l2_writeIdx] = -1;
                    outputDST2[l2_writeIdx++] = l2_id;
                }
            }
            
        }

        for (int l2 = 0 ; l2 < sampleNUM2 ; l2++) {
            int l3_id = outputSRC2[i * sampleNUM2 + l2];
            if (l3_id > 0) {
                int l3_writeIdx = i*sampleNUM2*sampleNUM3 + l2*sampleNUM3;
                int l3_idStart = boundList[l3_id];
                int l3_idEnd = boundList[l3_id+1];
                int l3_neirNUM = l3_idEnd - l3_idStart;
                for (int l = 0 ; l < l3_neirNUM && l < sampleNUM3 ; l++) {
                    random_value = curand(&state) % l3_neirNUM; 
                    outputSRC3[l3_writeIdx] = graphEdge[l3_idStart + random_value];
                    outputDST3[l3_writeIdx++] = l3_id;
                }
                for (int l = l3_neirNUM; l < sampleNUM3 ; l++) {
                    outputSRC3[l3_writeIdx] = -1;
                    outputDST3[l3_writeIdx++] = l3_id;
                }
            } else {
                int l3_writeIdx = i*sampleNUM2*sampleNUM3 + l2*sampleNUM3;
                for (int l = 0 ; l < sampleNUM2 ; l++) {
                    outputSRC3[l3_writeIdx] = -1;
                    outputDST3[l3_writeIdx++] = l3_id;
                }
            }
        }
    }
}

void launch_sample_full(int* outputSRC1,
                 int* outputDST1,
                 const int* graphEdge,
                 const int* boundList,
                 const int* trainNode,
                 int n,
                 const int gpuDeviceIndex
                 ) {
    dim3 grid((n + 1023) / 1024);
    dim3 block(1024);
    
    /* 指定使用的GPU序号 [0,torch.cuda.device_count()) */
    int deviceCount;
    cudaGetDeviceCount(&deviceCount);
    if (deviceCount == 0) {
        //printf("No GPU devices found.\n");
        return;
    }
    else if(gpuDeviceIndex >= deviceCount || gpuDeviceIndex < 0){
        //printf("Wrong GPU Device Index:%d , Select Default Device Index:0 cuda:0.\n",gpuDeviceIndex);
        cudaSetDevice(0);
    }
    else{
        //printf("Select GPU Device Index:%d , Please Prepare Pytorch Data tensor.to(device='cuda:%d')\n",gpuDeviceIndex,gpuDeviceIndex);
        cudaSetDevice(gpuDeviceIndex);
    }

    sample_full_kernel<<<grid, block>>>(outputSRC1, outputDST1, graphEdge, boundList, trainNode, n);
}

void launch_sample_1hop(int* outputSRC1,
                        int* outputDST1, 
                        const int* graphEdge,
                        const int* boundList,
                        const int* trainNode,
                        int sampleNUM1,
                        int nodeNUM,
                        const int gpuDeviceIndex
                        ) {
    dim3 grid((nodeNUM + 1023) / 1024);
    dim3 block(1024);
    unsigned long long seed = std::chrono::system_clock::now().time_since_epoch().count();
    
    /* 指定使用的GPU序号 [0,torch.cuda.device_count()) */
    int deviceCount;
    cudaGetDeviceCount(&deviceCount);
    if (deviceCount == 0) {
        //printf("No GPU devices found.\n");
        return;
    }
    else if(gpuDeviceIndex >= deviceCount || gpuDeviceIndex < 0){
        //printf("Wrong GPU Device Index:%d , Select Default Device Index:0 cuda:0.\n",gpuDeviceIndex);
        cudaSetDevice(0);
    }
    else{
        //printf("Select GPU Device Index:%d , Please Prepare Pytorch Data tensor.to(device='cuda:%d')\n",gpuDeviceIndex,gpuDeviceIndex);
        cudaSetDevice(gpuDeviceIndex);
    }

    

    //auto t_beg = std::chrono::high_resolution_clock::now();
    sample1Hop<<<grid, block>>>(
        outputSRC1,outputDST1,graphEdge,
        boundList,trainNode,sampleNUM1,
        nodeNUM,seed);
    //auto t_end = std::chrono::high_resolution_clock::now();
    //printf("sample1Hop time in function`launch_sample_1hop` : %lf ms\n",std::chrono::duration<double, std::milli>(t_end-t_beg).count());
}

void launch_sample_2hop(int* outputSRC1,
                        int* outputDST1,
                        int* outputSRC2,
                        int* outputDST2,
                        const int* graphEdge,
                        const int* boundList,
                        const int* trainNode,
                        int sampleNUM1,
                        int sampleNUM2,
                        int nodeNUM,
                        const int gpuDeviceIndex
                        ) {
    dim3 grid((nodeNUM + 1023) / 1024);
    dim3 block(1024);
    unsigned long long seed = std::chrono::system_clock::now().time_since_epoch().count();

    /* 指定使用的GPU序号 [0,torch.cuda.device_count()) */
    int deviceCount;
    cudaGetDeviceCount(&deviceCount);
    if (deviceCount == 0) {
        //printf("No GPU devices found.\n");
        return;
    }
    else if(gpuDeviceIndex >= deviceCount || gpuDeviceIndex < 0){
        //printf("Wrong GPU Device Index:%d , Select Default Device Index:0 cuda:0.\n",gpuDeviceIndex);
        cudaSetDevice(0);
    }
    else{
        //printf("Select GPU Device Index:%d , Please Prepare Pytorch Data tensor.to(device='cuda:%d')\n",gpuDeviceIndex,gpuDeviceIndex);
        cudaSetDevice(gpuDeviceIndex);
    }

    //auto t_beg = std::chrono::high_resolution_clock::now();
    sample2Hop<<<grid, block>>>(
        outputSRC1,outputDST1,outputSRC2,
        outputDST2,graphEdge,boundList,
        trainNode,sampleNUM1,sampleNUM2,nodeNUM,seed);
    //auto t_end = std::chrono::high_resolution_clock::now();
    //printf("sample2Hop time in function`launch_sample_2hop` : %lf ms\n",std::chrono::duration<double, std::milli>(t_end-t_beg).count());
}

void launch_sample_3hop(int* outputSRC1,int* outputDST1,
                        int* outputSRC2,int* outputDST2,
                        int* outputSRC3,int* outputDST3,
                        const int* graphEdge,
                        const int* boundList,
                        const int* trainNode,
                        int sampleNUM1,int sampleNUM2,int sampleNUM3,
                        int nodeNUM,
                        const int gpuDeviceIndex
                        ) {
    dim3 grid((nodeNUM + 1023) / 1024);
    dim3 block(1024);
    unsigned long long seed = std::chrono::system_clock::now().time_since_epoch().count();

    /* 指定使用的GPU序号 [0,torch.cuda.device_count()) */
    int deviceCount;
    cudaGetDeviceCount(&deviceCount);
    if (deviceCount == 0) {
        //printf("No GPU devices found.\n");
        return;
    }
    else if(gpuDeviceIndex >= deviceCount || gpuDeviceIndex < 0){
        //printf("Wrong GPU Device Index:%d , Select Default Device Index:0 cuda:0.\n",gpuDeviceIndex);
        cudaSetDevice(0);
    }
    else{
        //printf("Select GPU Device Index:%d , Please Prepare Pytorch Data tensor.to(device='cuda:%d')\n",gpuDeviceIndex,gpuDeviceIndex);
        cudaSetDevice(gpuDeviceIndex);
    }

    //auto t_beg = std::chrono::high_resolution_clock::now();
    sample3Hop<<<grid, block>>>(
        outputSRC1,outputDST1,outputSRC2,
        outputDST2,outputSRC3,outputDST3,
        graphEdge,boundList,trainNode,
        sampleNUM1,sampleNUM2,sampleNUM3,nodeNUM,seed);
    //auto t_end = std::chrono::high_resolution_clock::now();
    //printf("sample3Hop time in function`launch_sample_3hop` : %lf ms\n",std::chrono::duration<double, std::milli>(t_end-t_beg).count());
}

__global__ void func0(int* cacheData0,
                    int* cacheData1,
                    const int* edges,
                    const int cacheData0Len,
                    const int cacheData1Len,
                    const int edgesLen,
                    const int graphEdgeNUM)
{
    int lastid = -1;
    int endidx = -1;
    int nextidx = -1;
    for(int i = 0;i < edgesLen/2;i++)
    {
        int src = edges[i*2];
        int dst = edges[i*2 + 1];
        if(dst != lastid)
        {
            if(cacheData1Len > dst*2+2){
                endidx = cacheData1[dst*2+1];
                nextidx = cacheData1[dst*2+2];
            }
            else{
                nextidx = graphEdgeNUM;
            }
            lastid = dst;
        }
        
        if(endidx < nextidx)
        {
            if(endidx < cacheData0Len)
                cacheData0[endidx] = src;
            endidx += 1;
        }
    }
}

__global__ void func1(int* cacheData0,
                    int* cacheData1,
                    const int* edges,
                    const int* bound,
                    const int cacheData0Len,
                    const int cacheData1Len,
                    const int edgesLen,
                    const int boundLen,
                    const int graphEdgeNUM)
{
    int idx = blockIdx.x * blockDim.x + threadIdx.x;
    if(idx >= (boundLen-1))
        return;
    const int lowerBound = bound[idx];
    const int upperBound = bound[idx+1];
    const int dst = edges[lowerBound+1];
    int endidx = -1;
    int nextidx = -1;
    if(cacheData1Len > dst*2+2)
    {
        endidx = cacheData1[dst*2+1];
        nextidx = cacheData1[dst*2+2];
    }
    else
    {
        nextidx = graphEdgeNUM;
    }

    int j = endidx;
    for(int i = lowerBound;i < upperBound;i+=2)
    {
        int src = edges[i];
        if(j < nextidx)
        {
            if(j < cacheData0Len)
                cacheData0[j] = src;
            j++;
        }
    }
}

__global__ void func2(int* cacheData0,
                    int* cacheData1,
                    const int* edges,
                    const int* bound,
                    const int cacheData0Len,
                    const int cacheData1Len,
                    const int edgesLen,
                    const int boundLen,
                    const int graphEdgeNUM)
{
    if(blockIdx.x >= (boundLen-1))
        return;
    
    const int lowerBound = bound[blockIdx.x];
    const int upperBound = bound[blockIdx.x+1];
    const int dst = edges[lowerBound+1];
    int endidx = -1;
    int nextidx = -1;
    if(cacheData1Len > dst*2+2)
    {
        endidx = cacheData1[dst*2+1];
        nextidx = cacheData1[dst*2+2];
    }
    else
    {
        nextidx = graphEdgeNUM;
    }

    // if(((lowerBound+2*threadIdx.x)<upperBound) && (endidx+threadIdx.x < nextidx) && (endidx+threadIdx.x < cacheData0Len))
    //     cacheData0[endidx+threadIdx.x] = edges[lowerBound+2*threadIdx.x];
    

    for(int i = threadIdx.x;(lowerBound+2*i)<upperBound;i+=1024)
        if((endidx+i) < nextidx && (endidx+i) < cacheData0Len)
            cacheData0[endidx+i] = edges[lowerBound+2*i];
}

void lanch_loading_halo(int* cacheData0,
                        int* cacheData1,
                        const int* edges,
                        const int* bound,
                        const int cacheData0Len,
                        const int cacheData1Len,
                        const int edgesLen,
                        const int boundLen,
                        const int graphEdgeNUM,
                        const int gpuDeviceIndex)
{   
    /* 指定使用的GPU序号 [0,torch.cuda.device_count()) */
    int deviceCount;
    cudaGetDeviceCount(&deviceCount);
    if (deviceCount == 0) {
        //printf("No GPU devices found.\n");
        return;
    }
    else if(gpuDeviceIndex >= deviceCount || gpuDeviceIndex < 0){
        //printf("Wrong GPU Device Index:%d , Select Default Device Index:0 cuda:0.\n",gpuDeviceIndex);
        cudaSetDevice(0);
    }
    else{
        //printf("Select GPU Device Index:%d , Please Prepare Pytorch Data tensor.to(device='cuda:%d')\n",gpuDeviceIndex,gpuDeviceIndex);
        cudaSetDevice(gpuDeviceIndex);
    }

    dim3 grid((boundLen+1023)/1024);
    dim3 block(1024);
    func2<<<grid,block>>>(cacheData0,
                        cacheData1,
                        edges,
                        bound,
                        cacheData0Len,
                        cacheData1Len,
                        edgesLen,
                        boundLen,
                        graphEdgeNUM);
    
}

void lanch_loading_halo0(int* cacheData0,
                        int* cacheData1,
                        const int* edges,
                        const int cacheData0Len,
                        const int cacheData1Len,
                        const int edgesLen,
                        const int graphEdgeNUM,
                        const int gpuDeviceIndex)
{   
    /* 指定使用的GPU序号 [0,torch.cuda.device_count()) */
    int deviceCount;
    cudaGetDeviceCount(&deviceCount);
    if (deviceCount == 0) {
        //printf("No GPU devices found.\n");
        return;
    }
    else if(gpuDeviceIndex >= deviceCount || gpuDeviceIndex < 0){
        //printf("Wrong GPU Device Index:%d , Select Default Device Index:0 cuda:0.\n",gpuDeviceIndex);
        cudaSetDevice(0);
    }
    else{
        //printf("Select GPU Device Index:%d , Please Prepare Pytorch Data tensor.to(device='cuda:%d')\n",gpuDeviceIndex,gpuDeviceIndex);
        cudaSetDevice(gpuDeviceIndex);
    }

    dim3 grid(1);
    dim3 block(1);
    
    func0<<<grid,block>>>(cacheData0,
                        cacheData1,
                        edges,
                        cacheData0Len,
                        cacheData1Len,
                        edgesLen,
                        graphEdgeNUM);
}