<script setup lang="ts">
defineEmits<{ open: [process: string] }>()
const processes = [
  ['A 입고', '가동', 320], ['B 슬리팅', '가동', 310], ['C 프레스', '이상', 0],
  ['D 용접', '대기', 280], ['E 도장', '가동', 275], ['F 출고', '가동', 1180],
] as const
</script>

<template>
  <main class="page" style="grid-template: minmax(0, 1fr) minmax(0, 1fr) / repeat(3, minmax(0, 1fr))">
    <section class="box" style="grid-column: 1 / -1">
      <h2>공정 흐름 · 가동 4 / 대기 1 / 이상 1 (클릭 → 상세)</h2>
      <div class="cards">
        <div v-for="[name, state, qty] in processes" :key="name" :class="'s-' + state" style="cursor: pointer" @click="$emit('open', name)">
          {{ name }}<b>{{ state }}</b>처리 {{ qty }}
        </div>
      </div>
    </section>
    <section class="box">
      <h2>오늘 생산</h2>
      <div class="cards">
        <div>양품<b>1,240</b></div>
        <div>출고<b>1,180</b></div>
        <div>달성률<b>82%</b></div>
      </div>
    </section>
    <section class="box">
      <h2>출고 검사</h2>
      <div class="fill" style="gap: 20px">
        <div class="pie" style="background: conic-gradient(#7b7 0 96%, #e66 0 98.6%, #bbb 0)"></div>
        <div style="text-align: left">
          <div><span class="dot s-가동"></span> 양품 1,240</div>
          <div><span class="dot s-이상"></span> 불량 32</div>
          <div><span class="dot" style="background: #bbb"></span> 대기 18</div>
        </div>
      </div>
    </section>
    <section class="box">
      <h2>알림</h2>
      <div class="list">
        <div><span class="dot s-이상"></span> C 프레스 · 진동 이상 · 12분</div>
        <div><span class="dot s-대기"></span> D 용접 · 자재 대기 · 해제</div>
      </div>
    </section>
  </main>
</template>
