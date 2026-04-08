#!/bin/sh
# List Kubernetes nodes with key status fields

set -eu

#COLUMNS="NAME:metadata.name,IP:status.addresses[?(@.type=='InternalIP')].address,READY:status.conditions[?(@.type=='Ready')].status,CORDON:spec.unschedulable,TAINT:spec.taints[?(@)].effect,DRAINING:metadata.annotations['draino\.coreweave\.cloud\/draining'],NCORE:metadata.labels['node\.coreweave\.cloud\/version'],PAYLOAD:metadata.labels['node\.coreweave\.cloud\/payload-version'],K8SVER:status.nodeInfo.kubeletVersion,INT-OWNER:metadata.labels['private\.coreweave\.cloud/internal-owner'],STATE:metadata.labels['node\.coreweave\.cloud\/state'],RESERVED:metadata.labels['node\.coreweave\.cloud\/reserved'],CLUSTER:metadata.labels['cks\.coreweave\.com\/cluster'],RACK:metadata.labels['node\.coreweave\.cloud\/rack'],RU:metadata.labels['node\.coreweave\.cloud\/rack-unit']"

COLUMNS="NAME:metadata.name,IP:status.addresses[?(@.type=='InternalIP')].address,READY:status.conditions[?(@.type=='Ready')].status,CORDON:spec.unschedulable,TAINT:spec.taints[?(@)].effect,DRAINING:metadata.annotations['draino\.coreweave\.cloud\/draining'],INT-OWNER:metadata.labels['private\.coreweave\.cloud/internal-owner'],STATE:metadata.labels['node\.coreweave\.cloud\/state'],PENDINGSTATE:metadata.labels['node\.coreweave\.cloud\/pending-state'],RESERVED:metadata.labels['node\.coreweave\.cloud\/reserved'],CLUSTER:metadata.labels['cks\.coreweave\.com\/cluster'],RACK:metadata.labels['node\.coreweave\.cloud\/rack'],RU:metadata.labels['node\.coreweave\.cloud\/rack-unit']"

exec kubectl get nodes -o "custom-columns=${COLUMNS}" "$@"
