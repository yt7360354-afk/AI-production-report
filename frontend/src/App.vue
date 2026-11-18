<script setup lang="ts">
import { ref } from 'vue'
import Monitoring from './pages/Monitoring.vue'
import ProcessDetail from './pages/ProcessDetail.vue'
import Utilization from './pages/Utilization.vue'
import Maintenance from './pages/Maintenance.vue'

// shortcut: ref로 화면 전환, 실제 개발 시 vue-router로 교체
const page = ref<'monitor' | 'detail' | 'util' | 'pm'>('monitor')
const process = ref('A')

function openDetail(p: string) {
  process.value = p
  page.value = 'detail'
}
</script>

<template>
  <header class="nav">
    <strong>라인가동현황</strong>
    <button :class="{ on: page === 'monitor' || page === 'detail' }" @click="page = 'monitor'">모니터링</button>
    <button :class="{ on: page === 'util' }" @click="page = 'util'">가동률</button>
    <button :class="{ on: page === 'pm' }" @click="page = 'pm'">예지보전</button>
    <select><option>전체 공정</option><option v-for="p in 'ABCDEF'" :key="p">{{ p }}</option></select>
    <span class="right">● 수신 상태 · 마지막 수신 시각</span>
  </header>

  <Monitoring v-if="page === 'monitor'" @open="openDetail" />
  <ProcessDetail v-else-if="page === 'detail'" :process="process" @back="page = 'monitor'" />
  <Utilization v-else-if="page === 'util'" />
  <Maintenance v-else />
</template>
