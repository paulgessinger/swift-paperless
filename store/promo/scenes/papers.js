// Paper artwork shared by the promo scenes: #sym-letter, #sym-invoice and
// #sym-receipt, each drawn centred on the origin. Injected into the first
// <defs> so scenes can <use> them.
document.querySelector("svg defs").insertAdjacentHTML("beforeend", `
    <!-- A4 letter, 420×594, centred on origin -->
    <g id="sym-letter">
      <rect x="-210" y="-297" width="420" height="594" rx="6" fill="#fff"/>
      <path d="M-160 -248 q10 -16 20 0 q-10 16 -20 0z" fill="#2e7d32"/>
      <rect x="-128" y="-256" width="120" height="16" rx="4" fill="#17541f"/>
      <rect x="-160" y="-210" width="320" height="120" rx="3" fill="#b9c6c9"/>
      <path d="M-160 -90 L-60 -150 L40 -110 L160 -170 L160 -90z" fill="#8a9a7c"/>
      <g fill="#c9c9c9">
        <rect x="-160" y="-66" width="150" height="8" rx="4"/><rect x="10" y="-66" width="150" height="8" rx="4"/>
        <rect x="-160" y="-46" width="140" height="8" rx="4"/><rect x="10" y="-46" width="145" height="8" rx="4"/>
        <rect x="-160" y="-26" width="150" height="8" rx="4"/><rect x="10" y="-26" width="130" height="8" rx="4"/>
        <rect x="-160" y="-6"  width="120" height="8" rx="4"/><rect x="10" y="-6"  width="150" height="8" rx="4"/>
        <rect x="-160" y="14"  width="150" height="8" rx="4"/><rect x="10" y="14"  width="140" height="8" rx="4"/>
        <rect x="-160" y="34"  width="135" height="8" rx="4"/><rect x="10" y="34"  width="150" height="8" rx="4"/>
        <rect x="-160" y="54"  width="150" height="8" rx="4"/><rect x="10" y="54"  width="110" height="8" rx="4"/>
        <rect x="-160" y="74"  width="145" height="8" rx="4"/><rect x="10" y="74"  width="150" height="8" rx="4"/>
        <rect x="-160" y="94"  width="150" height="8" rx="4"/><rect x="10" y="94"  width="150" height="8" rx="4"/>
        <rect x="-160" y="114" width="100" height="8" rx="4"/><rect x="10" y="114" width="135" height="8" rx="4"/>
        <rect x="-160" y="134" width="150" height="8" rx="4"/><rect x="10" y="134" width="150" height="8" rx="4"/>
        <rect x="-160" y="154" width="140" height="8" rx="4"/><rect x="10" y="154" width="120" height="8" rx="4"/>
        <rect x="-160" y="174" width="150" height="8" rx="4"/><rect x="10" y="174" width="150" height="8" rx="4"/>
        <rect x="-160" y="194" width="120" height="8" rx="4"/><rect x="10" y="194" width="145" height="8" rx="4"/>
      </g>
      <rect x="-160" y="232" width="90" height="10" rx="4" fill="#555"/>
    </g>

    <!-- Invoice with a table -->
    <g id="sym-invoice">
      <rect x="-210" y="-297" width="420" height="594" rx="6" fill="#fff"/>
      <rect x="60" y="-250" width="100" height="16" rx="4" fill="#17541f"/>
      <g fill="#c9c9c9">
        <rect x="-160" y="-250" width="110" height="9" rx="4"/>
        <rect x="-160" y="-230" width="90" height="9" rx="4"/>
        <rect x="-160" y="-210" width="100" height="9" rx="4"/>
        <rect x="60" y="-220" width="90" height="8" rx="4"/>
        <rect x="60" y="-204" width="70" height="8" rx="4"/>
      </g>
      <rect x="-160" y="-160" width="180" height="18" rx="4" fill="#333"/>
      <rect x="-160" y="-100" width="320" height="26" fill="#e7ece7"/>
      <g stroke="#d6d6d6" stroke-width="3">
        <line x1="-160" y1="-40" x2="160" y2="-40"/><line x1="-160" y1="0" x2="160" y2="0"/>
        <line x1="-160" y1="40" x2="160" y2="40"/><line x1="-160" y1="80" x2="160" y2="80"/>
      </g>
      <g fill="#bdbdbd">
        <rect x="-150" y="-62" width="120" height="8" rx="4"/><rect x="90" y="-62" width="60" height="8" rx="4"/>
        <rect x="-150" y="-22" width="100" height="8" rx="4"/><rect x="90" y="-22" width="60" height="8" rx="4"/>
        <rect x="-150" y="18" width="130" height="8" rx="4"/><rect x="90" y="18" width="60" height="8" rx="4"/>
        <rect x="-150" y="58" width="90" height="8" rx="4"/><rect x="90" y="58" width="60" height="8" rx="4"/>
      </g>
      <rect x="40" y="104" width="120" height="20" rx="4" fill="#17541f"/>
      <g fill="#d2d2d2">
        <rect x="-160" y="170" width="320" height="8" rx="4"/>
        <rect x="-160" y="190" width="300" height="8" rx="4"/>
        <rect x="-160" y="210" width="260" height="8" rx="4"/>
      </g>
    </g>

    <!-- Narrow receipt with a torn edge, 300×640 -->
    <g id="sym-receipt">
      <path d="M-150 -320 H150 V300 l-18.75 20 l-18.75 -20 l-18.75 20 l-18.75 -20 l-18.75 20 l-18.75 -20 l-18.75 20 l-18.75 -20 l-18.75 20 l-18.75 -20 l-18.75 20 l-18.75 -20 l-18.75 20 l-18.75 -20 l-18.75 20 l-18.75 -20 z" fill="#fffdf8"/>
      <rect x="-70" y="-280" width="140" height="18" rx="4" fill="#333"/>
      <g fill="#c4c4c4">
        <rect x="-90" y="-248" width="180" height="8" rx="4"/>
        <rect x="-110" y="-190" width="120" height="8" rx="4"/><rect x="60" y="-190" width="50" height="8" rx="4"/>
        <rect x="-110" y="-165" width="90" height="8" rx="4"/><rect x="60" y="-165" width="50" height="8" rx="4"/>
        <rect x="-110" y="-140" width="140" height="8" rx="4"/><rect x="60" y="-140" width="50" height="8" rx="4"/>
        <rect x="-110" y="-115" width="100" height="8" rx="4"/><rect x="60" y="-115" width="50" height="8" rx="4"/>
        <rect x="-110" y="-90" width="110" height="8" rx="4"/><rect x="60" y="-90" width="50" height="8" rx="4"/>
      </g>
      <line x1="-110" y1="-55" x2="110" y2="-55" stroke="#bbb" stroke-width="3" stroke-dasharray="8 8"/>
      <rect x="-110" y="-30" width="80" height="14" rx="4" fill="#333"/>
      <rect x="40" y="-30" width="70" height="14" rx="4" fill="#333"/>
      <g fill="#333">
        <rect x="-90" y="60" width="6" height="80"/><rect x="-78" y="60" width="3" height="80"/>
        <rect x="-68" y="60" width="9" height="80"/><rect x="-52" y="60" width="3" height="80"/>
        <rect x="-42" y="60" width="6" height="80"/><rect x="-30" y="60" width="3" height="80"/>
        <rect x="-20" y="60" width="9" height="80"/><rect x="-4" y="60" width="6" height="80"/>
        <rect x="8" y="60" width="3" height="80"/><rect x="18" y="60" width="9" height="80"/>
        <rect x="34" y="60" width="3" height="80"/><rect x="44" y="60" width="6" height="80"/>
        <rect x="56" y="60" width="3" height="80"/><rect x="66" y="60" width="9" height="80"/>
        <rect x="82" y="60" width="6" height="80"/>
      </g>
    </g>
`);
