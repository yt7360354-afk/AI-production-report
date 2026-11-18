<script setup lang="ts">
import MiniChart from '../components/MiniChart.vue'
const equips = [
  ['C 프레스 #2', '위험', 's-이상'], ['D 용접 #1', '주의', 's-정지'], ['E 도장 #1', '데이터 부족', 's-대기'],
  ['A 입고 #1', '정상', 's-가동'], ['B 슬리팅 #1', '정상', 's-가동'],
] as const
</script>

<template>
  <main class="page" style="grid-template: minmax(0, 1.5fr) minmax(0, 1fr) / minmax(0, 1fr) minmax(0, 2fr)">
    <section class="box" style="grid-row: span 2">
      <h2>설비 상태 (위험 순)</h2>
      <div class="list">
        <div v-for="[name, label, cls] in equips" :key="name"><span class="dot" :class="cls"></span> {{ name }} · {{ label }}</div>
      </div>
    </section>
    <section class="box">
      <h2>C 프레스 #2 온도 (점선 = 기준값)</h2>
      <MiniChart type="line" :data="[60, 62, 61, 63, 66, 65, 70, 74, 78, 81]" :limit="75" />
    </section>
    <section class="box">
      <h2>기준값 경보 · 조치 이력</h2>
      <div class="list">
        <div><span class="dot s-이상"></span> 온도 81 / 기준 75 · 8분 초과</div>
        <div><span class="dot s-정지"></span> 지난주 · 베어링 교체</div>
      </div>
    </section>
  </main>
</template>
