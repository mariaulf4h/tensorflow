// RUN: tf-opt %s -tf-tpu-resource-partition | FileCheck %s

func private @computation(%arg0: tensor<i32>) -> tensor<i32>

// CHECK-LABEL: func @read_write_resource
// CHECK-SAME: ([[ARG0:%.+]]: tensor<!tf.resource<tensor<i32>>>, [[ARG1:%.+]]: tensor<!tf.resource<tensor<i32>>>)
func @read_write_resource(%arg0: tensor<!tf.resource<tensor<i32>>>, %arg1: tensor<!tf.resource<tensor<i32>>>) {
  // CHECK-DAG:  [[READ0:%.+]] = "tf.ReadVariableOp"([[ARG0]])
  // CHECK-DAG:  [[READ1:%.+]] = "tf.ReadVariableOp"([[ARG1]])
  // CHECK:      [[INPUT:%.+]] = "tf.TPUPartitionedInput"([[READ0]], [[READ1]])
  // CHECK-SAME: _XlaSharding = ""
  // CHECK-SAME: partition_dim = -1
  %0 = "tf.TPUPartitionedInput"(%arg0, %arg1) {N = 2 : i64, _XlaSharding = "", partition_dim = -1 : i64} : (tensor<!tf.resource<tensor<i32>>>, tensor<!tf.resource<tensor<i32>>>) -> tensor<!tf.resource<tensor<i32>>>
  %1 = "tf.ReadVariableOp"(%0) : (tensor<!tf.resource<tensor<i32>>>) -> tensor<i32>
  // CHECK:      [[COMPUTATION:%.+]] = "tf_device.cluster_func"([[INPUT]])
  %2 = "tf_device.cluster_func"(%1) {func = @computation, use_spmd_for_xla_partitioning = true} : (tensor<i32>) -> tensor<i32>
  // CHECK:      [[OUTPUT:%.+]]:2 = "tf.TPUPartitionedOutput"([[COMPUTATION]])
  // CHECK-SAME: _XlaSharding = ""
  // CHECK-SAME: partition_dim = -1
  // CHECK-DAG:  "tf.AssignVariableOp"([[ARG0]], [[OUTPUT]]#0)
  // CHECK-DAG:  "tf.AssignVariableOp"([[ARG1]], [[OUTPUT]]#1)
  "tf.AssignVariableOp"(%0, %2) : (tensor<!tf.resource<tensor<i32>>>, tensor<i32>) -> ()
  return
}

// CHECK-LABEL: func @read_only_resource
// CHECK-SAME: ([[ARG0:%.+]]: tensor<!tf.resource<tensor<i32>>>, [[ARG1:%.+]]: tensor<!tf.resource<tensor<i32>>>)
func @read_only_resource(%arg0: tensor<!tf.resource<tensor<i32>>>, %arg1: tensor<!tf.resource<tensor<i32>>>) -> tensor<i32> {
  // CHECK-DAG:  [[READ0:%.+]] = "tf.ReadVariableOp"([[ARG0]])
  // CHECK-DAG:  [[READ1:%.+]] = "tf.ReadVariableOp"([[ARG1]])
  // CHECK:      [[INPUT:%.+]] = "tf.TPUPartitionedInput"([[READ0]], [[READ1]])
  // CHECK-SAME: _XlaSharding = ""
  // CHECK-SAME: partition_dim = -1
  %0 = "tf.TPUPartitionedInput"(%arg0, %arg1) {N = 2 : i64, _XlaSharding = "", partition_dim = -1 : i64} : (tensor<!tf.resource<tensor<i32>>>, tensor<!tf.resource<tensor<i32>>>) -> tensor<!tf.resource<tensor<i32>>>
  %1 = "tf.ReadVariableOp"(%0) : (tensor<!tf.resource<tensor<i32>>>) -> tensor<i32>
  // CHECK:      "tf_device.cluster_func"([[INPUT]])
  %2 = "tf_device.cluster_func"(%1) {func = @computation, use_spmd_for_xla_partitioning = true} : (tensor<i32>) -> tensor<i32>
  // CHECK-NOT:  tf.TPUPartitionedOutput
  // CHECK-NOT:  tf.AssignVariableOp
  return %2 : tensor<i32>
}

// Tests unsupported cases and IR are not modified.

// CHECK-LABEL: func @no_spmd
// CHECK-SAME: ([[ARG0:%.+]]: tensor<!tf.resource<tensor<i32>>>, [[ARG1:%.+]]: tensor<!tf.resource<tensor<i32>>>)
func @no_spmd(%arg0: tensor<!tf.resource<tensor<i32>>>, %arg1: tensor<!tf.resource<tensor<i32>>>) {
  // CHECK:      "tf.TPUPartitionedInput"([[ARG0]], [[ARG1]])
  %0 = "tf.TPUPartitionedInput"(%arg0, %arg1) {N = 2 : i64, _XlaSharding = "", partition_dim = -1 : i64} : (tensor<!tf.resource<tensor<i32>>>, tensor<!tf.resource<tensor<i32>>>) -> tensor<!tf.resource<tensor<i32>>>
  %1 = "tf.ReadVariableOp"(%0) : (tensor<!tf.resource<tensor<i32>>>) -> tensor<i32>
  %2 = "tf_device.cluster_func"(%1) {func = @computation} : (tensor<i32>) -> tensor<i32>
  // CHECK:      "tf.TPUPartitionedInput"([[ARG0]], [[ARG1]])
  %3 = "tf.TPUPartitionedInput"(%arg0, %arg1) {N = 2 : i64, _XlaSharding = "", partition_dim = -1 : i64} : (tensor<!tf.resource<tensor<i32>>>, tensor<!tf.resource<tensor<i32>>>) -> tensor<!tf.resource<tensor<i32>>>
  %4 = "tf.ReadVariableOp"(%3) : (tensor<!tf.resource<tensor<i32>>>) -> tensor<i32>
  %5 = "tf_device.cluster_func"(%4) {func = @computation, use_spmd_for_xla_partitioning = false} : (tensor<i32>) -> tensor<i32>
  return
}

// CHECK-LABEL: func @read_write_unpartitioned_resource
func @read_write_unpartitioned_resource(%arg0: tensor<!tf.resource<tensor<i32>>>) {
  // CHECK-NOT:  tf.TPUPartitionedInput
  %0 = "tf.ReadVariableOp"(%arg0) : (tensor<!tf.resource<tensor<i32>>>) -> tensor<i32>
  %1 = "tf_device.cluster_func"(%0) {func = @computation} : (tensor<i32>) -> tensor<i32>
  // CHECK-NOT:  tf.TPUPartitionedOutput
  "tf.AssignVariableOp"(%arg0, %1) : (tensor<!tf.resource<tensor<i32>>>, tensor<i32>) -> ()
  return
}

// CHECK-LABEL: func @read_only_unpartitioned_resource
func @read_only_unpartitioned_resource(%arg0: tensor<!tf.resource<tensor<i32>>>) {
  // CHECK-NOT:  tf.TPUPartitionedInput
  %0 = "tf.ReadVariableOp"(%arg0) : (tensor<!tf.resource<tensor<i32>>>) -> tensor<i32>
  %1 = "tf_device.cluster_func"(%0) {func = @computation} : (tensor<i32>) -> tensor<i32>
  // CHECK-NOT:  tf.TPUPartitionedOutput
  // CHECK-NOT:  tf.AssignVariableOp
  return
}

// CHECK-LABEL: func @invalid_sharding_read_only_resource
// CHECK-SAME: ([[ARG0:%.+]]: tensor<!tf.resource<tensor<i32>>>, [[ARG1:%.+]]: tensor<!tf.resource<tensor<i32>>>)
func @invalid_sharding_read_only_resource(%arg0: tensor<!tf.resource<tensor<i32>>>, %arg1: tensor<!tf.resource<tensor<i32>>>) {
  // CHECK:      "tf.TPUPartitionedInput"([[ARG0]], [[ARG1]])
  %0 = "tf.TPUPartitionedInput"(%arg0, %arg1) {N = 2 : i64, partition_dim = -1 : i64} : (tensor<!tf.resource<tensor<i32>>>, tensor<!tf.resource<tensor<i32>>>) -> tensor<!tf.resource<tensor<i32>>>
  %1 = "tf.ReadVariableOp"(%0) : (tensor<!tf.resource<tensor<i32>>>) -> tensor<i32>
  %2 = "tf_device.cluster_func"(%1) {func = @computation} : (tensor<i32>) -> tensor<i32>
  // "\08\01\1A\01\01\22\01\00" = Maximal(0) sharding.
  // CHECK:      "tf.TPUPartitionedInput"([[ARG0]], [[ARG1]])
  %3 = "tf.TPUPartitionedInput"(%arg0, %arg1) {N = 2 : i64, _XlaSharding = "\08\01\1A\01\01\22\01\00", partition_dim = -1 : i64} : (tensor<!tf.resource<tensor<i32>>>, tensor<!tf.resource<tensor<i32>>>) -> tensor<!tf.resource<tensor<i32>>>
  %4 = "tf.ReadVariableOp"(%3) : (tensor<!tf.resource<tensor<i32>>>) -> tensor<i32>
  %5 = "tf_device.cluster_func"(%4) {func = @computation} : (tensor<i32>) -> tensor<i32>
  return
}

// CHECK-LABEL: func @invalid_sharding_write_only_resource
// CHECK-SAME: ([[ARG0:%.+]]: tensor<!tf.resource<tensor<i32>>>, [[ARG1:%.+]]: tensor<!tf.resource<tensor<i32>>>, {{%.+}}: tensor<i32>)
func @invalid_sharding_write_only_resource(%arg0: tensor<!tf.resource<tensor<i32>>>, %arg1: tensor<!tf.resource<tensor<i32>>>, %arg2: tensor<i32>) {
  // CHECK:      "tf.TPUPartitionedInput"([[ARG0]], [[ARG1]])
  %0 = "tf.TPUPartitionedInput"(%arg0, %arg1) {N = 2 : i64, partition_dim = -1 : i64} : (tensor<!tf.resource<tensor<i32>>>, tensor<!tf.resource<tensor<i32>>>) -> tensor<!tf.resource<tensor<i32>>>
  %1 = "tf_device.cluster_func"(%arg2) {func = @computation} : (tensor<i32>) -> tensor<i32>
  "tf.AssignVariableOp"(%0, %1) : (tensor<!tf.resource<tensor<i32>>>, tensor<i32>) -> ()
  // "\08\01\1A\01\01\22\01\00" = Maximal(0) sharding.
  // CHECK:      "tf.TPUPartitionedInput"([[ARG0]], [[ARG1]])
  %2 = "tf.TPUPartitionedInput"(%arg0, %arg1) {N = 2 : i64, _XlaSharding = "\08\01\1A\01\01\22\01\00", partition_dim = -1 : i64} : (tensor<!tf.resource<tensor<i32>>>, tensor<!tf.resource<tensor<i32>>>) -> tensor<!tf.resource<tensor<i32>>>
  %3 = "tf_device.cluster_func"(%arg2) {func = @computation} : (tensor<i32>) -> tensor<i32>
  "tf.AssignVariableOp"(%2, %3) : (tensor<!tf.resource<tensor<i32>>>, tensor<i32>) -> ()
  return
}

// CHECK-LABEL: func @resource_read_multiple_users
// CHECK-SAME: ([[ARG0:%.+]]: tensor<!tf.resource<tensor<i32>>>, [[ARG1:%.+]]: tensor<!tf.resource<tensor<i32>>>) -> tensor<i32>
func @resource_read_multiple_users(%arg0: tensor<!tf.resource<tensor<i32>>>, %arg1: tensor<!tf.resource<tensor<i32>>>) -> tensor<i32> {
  // CHECK:      "tf.TPUPartitionedInput"([[ARG0]], [[ARG1]])
  %0 = "tf.TPUPartitionedInput"(%arg0, %arg1) {N = 2 : i64, _XlaSharding = "", partition_dim = -1 : i64} : (tensor<!tf.resource<tensor<i32>>>, tensor<!tf.resource<tensor<i32>>>) -> tensor<!tf.resource<tensor<i32>>>
  %1 = "tf.ReadVariableOp"(%0) : (tensor<!tf.resource<tensor<i32>>>) -> tensor<i32>
  %2 = "tf_device.cluster_func"(%1) {func = @computation} : (tensor<i32>) -> tensor<i32>
  return %1 : tensor<i32>
}

// CHECK-LABEL: func @partitioned_variable_multiple_users
// CHECK-SAME: ([[ARG0:%.+]]: tensor<!tf.resource<tensor<i32>>>, [[ARG1:%.+]]: tensor<!tf.resource<tensor<i32>>>) -> tensor<!tf.resource<tensor<i32>>>
func @partitioned_variable_multiple_users(%arg0: tensor<!tf.resource<tensor<i32>>>, %arg1: tensor<!tf.resource<tensor<i32>>>) -> tensor<!tf.resource<tensor<i32>>> {
  // CHECK:      "tf.TPUPartitionedInput"([[ARG0]], [[ARG1]])
  %0 = "tf.TPUPartitionedInput"(%arg0, %arg1) {N = 2 : i64, _XlaSharding = "", partition_dim = -1 : i64} : (tensor<!tf.resource<tensor<i32>>>, tensor<!tf.resource<tensor<i32>>>) -> tensor<!tf.resource<tensor<i32>>>
  %1 = "tf.ReadVariableOp"(%0) : (tensor<!tf.resource<tensor<i32>>>) -> tensor<i32>
  %2 = "tf_device.cluster_func"(%1) {func = @computation} : (tensor<i32>) -> tensor<i32>
  return %0 : tensor<!tf.resource<tensor<i32>>>
}

// CHECK-LABEL: func @non_resource_read_input_write_output
func @non_resource_read_input_write_output(%arg0: tensor<i32>) -> tensor<i32> {
  // CHECK-NOT:  tf.TPUPartitionedInput
  %0 = "tf_device.cluster_func"(%arg0) {func = @computation} : (tensor<i32>) -> tensor<i32>
  // CHECK-NOT:  tf.TPUPartitionedOutput
  return %0 : tensor<i32>
}
