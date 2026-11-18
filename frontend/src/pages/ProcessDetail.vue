<script setup lang="ts">
import MiniChart from '../components/MiniChart.vue'
defineProps<{ process: string }>()
defineEmits<{ back: [] }>()
</script>

<template>
  <main class="page" style="grid-template: auto minmax(0, 1fr) minmax(0, 1.5fr) / minmax(0, 1fr) minmax(0, 1fr)">
    <div style="grid-column: 1 / -1">
      <button @click="$emit('back')">← 뒤로</button> <strong>{{ process }} 상세</strong>
    </div>
    <section class="box">
      <h2>공정 상태</h2>
      <div class="cards">
        <div class="s-이상">상태<b>이상</b></div>
        <div>지속<b>12분</b></div>
      </div>
    </section>
    <section class="box">
      <h2>설비</h2>
      <div class="cards">
        <div class="s-가동">#1<b>가동</b></div>
        <div class="s-이상">#2<b>이상</b></div>
        <div class="s-가동">#3<b>가동</b></div>
      </div>
    </section>
    <section class="box">
      <h2>진동 추이 (점선 = 기준값)</h2>
      <MiniChart type="line" :data="[3, 3.2, 3.1, 3.4, 3.3, 3.8, 4.5, 5.2, 5.8, 6.1]" :limit="5" />
    </section>
    <section class="box">
      <h2>정지 사유 · 조치</h2>
      <div class="list">
        <div>사유: 원인 미확인 ▼</div>
        <div>조치 메모: ________</div>
        <div><button>저장</button></div>
      </div>
    </section>
  </main>
</template>
