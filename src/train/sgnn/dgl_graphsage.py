import torch
import torch.nn as nn
import torch.nn.functional as F
import torchmetrics.functional as MF
import dgl
import dgl.nn as dglnn
#from torch.utils.data import Dataset, DataLoader
import random
import copy
import tqdm
import argparse
import sklearn.metrics
import numpy as np
import time
import sys
import os
import json
from dgl.data import AsNodePredDataset
from ogb.nodeproppred import DglNodePropPredDataset
from dgl.dataloading import NeighborSampler, MultiLayerFullNeighborSampler

current_folder = os.path.abspath(os.path.dirname(__file__))
sys.path.append(current_folder+"/../../"+"load")
#from loader_dgl import CustomDataset
from loader import CustomDataset

class SAGE(nn.Module):
    def __init__(self, in_size, hid_size, out_size):
        super().__init__()
        self.layers = nn.ModuleList()
        self.layers.append(dglnn.SAGEConv(in_size, hid_size, 'mean'))
        self.layers.append(dglnn.SAGEConv(hid_size, out_size, 'mean'))
        self.dropout = nn.Dropout(0.5)
        self.hid_size = hid_size
        self.out_size = out_size

    def forward(self, blocks, x):
        h = x
        for l, (layer, block) in enumerate(zip(self.layers, blocks)):
            # print("block=",block)
            # print("block.device=",block.device)
            # print(h)
            h = layer(block, h)
            if l != len(self.layers) - 1:
                h = F.relu(h)
                h = self.dropout(h)
        #exit(-1)
        return h

    def inference(self, g, device, batch_size):
        """Conduct layer-wise inference to get all the node embeddings."""
        feat = g.ndata['feat']
        sampler = MultiLayerFullNeighborSampler(1, prefetch_node_feats=['feat'])
        dataloader = dgl.dataloading.DataLoader(
                g, torch.arange(g.num_nodes()).to(g.device), sampler, device=device,
                batch_size=batch_size, shuffle=False, drop_last=False,
                num_workers=0)
        buffer_device = torch.device('cpu')
        pin_memory = (buffer_device != device)

        for l, layer in enumerate(self.layers):
            y = torch.empty(
                g.num_nodes(), self.hid_size if l != len(self.layers) - 1 else self.out_size,
                device=buffer_device, pin_memory=pin_memory)
            feat = feat.to(device)
            for input_nodes, output_nodes, blocks in tqdm.tqdm(dataloader):
                x = feat[input_nodes]
                h = layer(blocks[0], x) # len(blocks) = 1
                if l != len(self.layers) - 1:
                    h = F.relu(h)
                    h = self.dropout(h)
                # by design, our output nodes are contiguous
                y[output_nodes[0]:output_nodes[-1]+1] = h.to(buffer_device)
            feat = y
        return y
    
def evaluate(model, graph, dataloader):
    model.eval()
    ys = []
    y_hats = []
    for it, (input_nodes, output_nodes, blocks) in enumerate(dataloader):
        with torch.no_grad():
            x = blocks[0].srcdata['feat']
            ys.append(blocks[-1].dstdata['label'].cpu().numpy())
            y_hats.append(model(blocks, x).argmax(1).cpu().numpy())
        predictions = np.concatenate(y_hats)
        labels = np.concatenate(ys)
    return sklearn.metrics.accuracy_score(labels, predictions)

def layerwise_infer(device, graph, nid, model, batch_size):
    model.eval()
    with torch.no_grad():
        pred = model.inference(graph, device, batch_size) # pred in buffer_device
        pred = pred[nid]
        label = graph.ndata['label'][nid].to(pred.device)
    label = label.squeeze()
    pred = pred.squeeze()
    return sklearn.metrics.classification_report(label.cpu().numpy(), pred.argmax(1).cpu().numpy(),zero_division=1)

def collate_fn(data):
    """
    data 输入结构介绍：
        [graph,feat]
    """
    return data[0]

def train(args, device, dataset, model):
    opt = torch.optim.Adam(model.parameters(), lr=1e-3, weight_decay=5e-4)
    train_loader = torch.utils.data.DataLoader(dataset=dataset, batch_size=1024, collate_fn=collate_fn,pin_memory=True)
    # 修改此处，epoch数必须同步修改json文件里的epoch数
    for epoch in range(50):
        start = time.time()
        total_loss = 0
        model.train()
        for it,(graph,feat,label,number) in enumerate(train_loader):
            # print("type(graph)=",type(graph))
            # print("type(feat)=",type(feat))
            # print("feat.device=",feat.device)
            # print("type(label)=",type(label))
            # print("type(number)=",type(number))
            #graph = [block.to('cuda') for block in graph]
            feat = feat.to('cuda:1')
            tmp = copy.deepcopy(graph)
            tmp = [block.to('cuda:1') for block in tmp]
            # print(tmp[0].device)
            # exit(-1)
            #print("type(graph)=",type(graph))
            #print("graph.device=",graph[0].device)
            #exit(-1)
            y_hat = model(tmp, feat)
            #print("y_hat len:{},label len:{},number:{}".format(len(y_hat),len(label),number))
            try:
                loss = F.cross_entropy(y_hat[1:number+1], label[:number].to(torch.int64).to('cuda:1'))
            except:
                print("graph:{},featLen:{},labelLen:{},predLen:{},number:{}".format(graph,feat.shape,label.shape,y_hat.shape,number))
            graph.clear()
            del graph
            del feat
            del label
            #torch.cuda.empty_cache()
            opt.zero_grad()
            loss.backward()
            opt.step()
            total_loss += loss.item()
        print("Epoch {:05d} | Loss {:.4f} |"
              .format(epoch, total_loss / (it+1)))

    dataset.changeMode("test")
    test_loader = torch.utils.data.DataLoader(dataset=dataset, batch_size=1024, collate_fn=collate_fn,pin_memory=True)
    #model.train()
    for graph,feat,label,number in test_loader:
        model.eval()
        with torch.no_grad():
            labels = []
            preds = []
            graph = [block.to('cuda:1') for block in graph]
            pred = model(graph, feat.to('cuda:1')) # pred in buffer_device
            preds.extend(pred[1:number+1])
            labels.extend(label[:number])
    newpreds = torch.zeros((len(preds),47),dtype=torch.float32)
    for index,pred in enumerate(preds):
        newpreds[index] = pred
    labels = torch.Tensor(labels).to(torch.int64).cpu().numpy()
    newpreds = newpreds.argmax(1).cpu().numpy()
    print(sklearn.metrics.classification_report(labels,newpreds,zero_division=1))
        # acc = evaluate(model, g, val_dataloader)
        # print("Epoch {:05d} | Loss {:.4f} | Accuracy {:.4f} "
        #       .format(epoch, total_loss / (it+1), acc.item()))
        # print("time :",time.time()-start)

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument("--mode", default='mixed', choices=['cpu', 'mixed', 'puregpu'],
                        help="Training mode. 'cpu' for CPU training, 'mixed' for CPU-GPU mixed training, "
                             "'puregpu' for pure-GPU training.")
    args = parser.parse_args()
    if not torch.cuda.is_available():
        args.mode = 'cpu'
    print(f'Training in {args.mode} mode.')
    print('Loading data')
    
    device = torch.device('cpu' if args.mode == 'cpu' else 'cuda:1')
    # create GraphSAGE model
    # in_size = g.ndata['feat'].shape[1]
    # out_size = dataset.num_classes
    model = SAGE(100, 256, 47).to('cuda:1')
    dataset = CustomDataset("./../../load/graphsage.json")
    print('Training...')
    train(args, device, dataset, model)

    # test the model
    print('Testing...')

    test_dataset = AsNodePredDataset(DglNodePropPredDataset('ogbn-products'))
    g = test_dataset[0]
    # g, dataset,train_idx,val_idx,test_idx= load_reddit()
    # data = (train_idx,val_idx,test_idx)
    g = g.to('cuda:1' if args.mode == 'puregpu' else 'cpu')

    print("Test Accuracy :\n",layerwise_infer(device, g, dataset.get_test_idx(2213091), model, batch_size=4096))
