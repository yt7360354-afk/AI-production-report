<script setup lang="ts">
import MiniChart from '../components/MiniChart.vue'
// 예시 타임라인: [상태, 길이]
const p1 = [['가동', 5], ['대기', 1], ['가동', 4]]
const p2 = [['가동', 3], ['정지', 2], ['가동', 5]]
const p3 = [['가동', 2], ['이상', 3], ['정지', 1], ['가동', 4]]
const timeline = [['A', p1], ['B', p2], ['C', p3], ['D', p1], ['E', p2], ['F', p1]] as const
</script>

<template>
  <main class="page" style="grid-template: auto minmax(0, 1fr) minmax(0, 1fr) / minmax(0, 1fr) minmax(0, 2fr)">
    <div style="grid-column: 1 / -1">
      기간 <button>일</button> <button>주</button> <button>월</button>
      <button style="float: right">다운로드</button>
    </div>
    <section class="box">
      <h2>오늘 가동</h2>
      <div class="cards">
        <div>가동률<b>85%</b></div>
        <div>정지<b>7회</b>2시간 24분</div>
      </div>
    </section>
    <section class="box">
      <h2>공정별 가동률 (%)</h2>
      <MiniChart type="bar" :data="[92, 88, 71, 85, 90, 95]" :labels="['A', 'B', 'C', 'D', 'E', 'F']" />
    </section>
    <section class="box">
      <h2>정지 원인 데이터 (건)</h2>
      <MiniChart type="bar" :data="[4, 5, 2, 3, 1]" :labels="['온도', '진동', '전류', '사이클', '미확인']" />
    </section>
    <section class="box">
      <h2>
        상태 타임라인 &nbsp;
        <small><span class="dot s-가동"></span> 가동 <span class="dot s-대기"></span> 대기 <span class="dot s-정지"></span> 정지 <span class="dot s-이상"></span> 이상</small>
      </h2>
      <div v-for="[name, segs] in timeline" :key="name" class="tl">
        {{ name }}
        <div><div v-for="([state, len], i) in segs" :key="i" :class="'s-' + state" :style="{ flex: len }"></div></div>
      </div>
    </section>
  </main>
</template>
