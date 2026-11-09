// 核心运行时出口：只暴露宿主服务与目录，不暴露仓储单例（ADR-003 §2.2）
export { HOST_API_VERSION, featureCatalog, findFeature } from './src/main/ets/host/CoreRuntime'
export { outlineService } from './src/main/ets/host/OutlineService'
