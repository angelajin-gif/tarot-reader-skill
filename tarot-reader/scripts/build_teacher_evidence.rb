#!/usr/bin/env ruby

require "json"
require "digest"
require "fileutils"
require "yaml"

# Deterministic release-local builder. Daniel and Dawn content below is a
# manually authored condensation of rendered source pages. Greer is normalized
# from the existing substantive card-entry anchors; Nichols is normalized from
# the authored chapter models and their chapter chains. No OCR text is copied
# into the release artifacts.
module TarotTeacherEvidenceBuilder
  ROOT = File.expand_path("..", __dir__).freeze
  REPO_ROOT = File.expand_path("../..", ROOT).freeze
  SNAPSHOT = File.join(ROOT, "references", "snapshot").freeze
  OUT = File.join(ROOT, "references", "teacher-evidence").freeze
  SOURCE_CHUNKS = {
    "daniel_16_lessons_zh" => File.join(REPO_ROOT, "reading", "daniel_16_lessons_zh", "source-chunks.jsonl"),
    "nichols_jung_tarot_en" => File.join(REPO_ROOT, "reading", "nichols_archetypal_journey_en", "source-chunks.jsonl")
  }.freeze
  NICHOLS_CHAPTERS = {
    "fool" => "ch03_the_fool", "magician" => "ch04_the_magician", "high_priestess" => "ch05_the_popess",
    "empress" => "ch06_the_empress", "emperor" => "ch07_the_emperor", "hierophant" => "ch08_the_pope",
    "lovers" => "ch09_the_lover", "chariot" => "ch10_the_chariot", "justice" => "ch11_justice",
    "hermit" => "ch12_the_hermit", "wheel_of_fortune" => "ch13_wheel_of_fortune", "strength" => "ch14_strength",
    "hanged_man" => "ch15_the_hanged_man", "death" => "ch16_death", "temperance" => "ch17_temperance",
    "devil" => "ch18_the_devil", "tower" => "ch19_the_tower", "star" => "ch20_the_star",
    "moon" => "ch21_the_moon", "sun" => "ch22_the_sun", "judgement" => "ch23_judgement",
    "world" => "ch24_the_world"
  }.freeze

  DANIEL = {
    "wands_ace" => ["雲中伸出的手握住發芽的權杖；作者把芽、葉與雲中出現的手連成新生與行動可能。", ["新行動", "主動性", "信心", "無限的潛能"], "把新局面先當成可嘗試的起點；信心與主動投入會比躁進更有用。", "工作可指新的工作方式或尚未確定的機會；關係可指新的互動或投入。"],
    "wands_two" => ["人物站在城牆上看向城外，右手托地球儀，左手握一支權杖，另一支固定在城牆上。", ["思考與計劃", "猶豫不決", "受限制的行動", "延遲"], "向外發展的視野與被固定的位置同時存在；計畫尚未轉成自由行動。", "工作可表現為想換工作卻未選定時機；物流或流程可比預定時間慢，需要備援。"],
    "wands_three" => ["人物站在高地看著海灣與出港的船，手扶一支權杖，另外兩支立在身後。", ["初步的成果", "合作及領導", "積極進取", "未知的旅程"], "已有基礎與初步成果，下一步需要合作、領導和面對尚未知道的風險。", "工作可指共同完成與擴展；關係可指已有基礎但仍需勇氣前進。"],
    "wands_four" => ["四支權杖搭成花門，人物在城堡前相聚，背景有城牆與穩定的空間。", ["成功及維持現狀", "慶祝及享受", "和平相處", "穩固及安全"], "成果需要被維持和共同慶祝；安定本身也是當前行動的一部分。", "工作可指穩定成果後的延續；關係可指和平相處與共同活動。"],
    "wands_five" => ["五個人物各持權杖，權杖方向交錯，彼此行動互相干擾。", ["努力進取", "立場觀點不同", "磨擦或衝突", "模仿"], "多個行動方向尚未協調；衝突也可能是看見不同方法與投射的場域。", "工作可指團隊競爭或方法不合；關係可指爭執與彼此模仿。"],
    "wands_six" => ["騎士騎馬，權杖上有花環；背景人物各持權杖，形成迎接與陪襯。", ["勝利者凱旋", "自信心", "榮譽", "讚美與支持"], "一段努力接近收尾，成果需要自信也需要承認支持者與團隊位置。", "工作可指完成階段性任務並獲肯定；關係可指得到鼓勵或公開支持。"],
    "wands_seven" => ["人物站在高地持一支權杖，下面六支權杖從不同方向向上。", ["優勢地位", "不同的挑戰", "堅持下去", "積極抵抗"], "已有位置但要持續應對不同壓力；主動守住立場比被動挨打更符合作者敘事。", "工作可指守住成果、處理競爭；關係可指面對外來壓力並清楚表態。"],
    "wands_eight" => ["八支權杖在空中朝同一方向飛行，畫面沒有停留的人物。", ["快速的行動", "共同的目標", "自由與空間", "忙碌"], "方向已較一致，速度增加；仍要留出空間處理同時到來的事項。", "工作可指快速推進或高工作量；關係可指互動變快，也可能需要空間。"],
    "wands_nine" => ["人物頭部包著繃布，手持權杖；身後八支權杖排列成防衛的圍籬。", ["受傷", "準備反擊", "防守策略", "延遲與等待"], "曾受影響使人提高警戒；下一步是準備和耐性，而非把防衛誤當成已發生的攻擊。", "工作可指保留原策略並準備意外；關係可指受傷後保持界線。"],
    "wands_ten" => ["人物彎身抱住十支權杖，身體被負荷遮住，前方只有一小段路。", ["壓力與勞累", "責任感", "得到", "緊抓不放"], "承擔已超過可舒適分配的量；成果與責任並存，但需要重新分工或放手。", "工作可指任務過多；關係可指把所有責任抓在自己身上。"],
    "cups_ace" => ["雲中手托出一只聖杯，水從杯中流出，杯上有十字圖形，水面有睡蓮。", ["感情的新開始", "豐富和滿足", "上天的祝福", "純潔無瑕"], "情感或關係有新的入口；作者把流動的情感、祝福感與可分享的滿足並置。", "單身可指新關係可能性；工作可指受祝福的開始或順利投入。"],
    "cups_two" => ["兩人各持聖杯，杯子高度相同，中央有雙蛇杖與翼形圖案。", ["平等的關係", "主動的付出", "強烈的吸引力", "良好的溝通"], "雙方位置平等且需要互相投入；吸引力不能取代溝通與承諾。", "可指伴侶、朋友或同事間的互惠，也可指衝突中主動說清楚。"],
    "cups_three" => ["三人各舉聖杯，人物靠近並跳舞，地面有果實與花朵。", ["慶祝", "歡樂的氣氛", "平等的合作", "應得的回報"], "共同分享與回報形成支持；但關係也可能只停留在娛樂或酒肉朋友。", "工作可指團隊完成；關係可指聚會、朋友支持或共同歡慶。"],
    "cups_four" => ["人物坐在樹下交叉雙手，面前有三只聖杯，雲中手再遞來一杯。", ["暫時休息", "沉思", "不滿意", "自己的想像"], "注意力停在既有不滿，新的選項已出現但尚未被接住；作者不把它直接定成必須行動。", "工作可指停滯與重新思考；關係可指標準過高或未看見現實條件。"],
    "cups_five" => ["披黑斗篷的人面向倒下的三杯，身後仍有兩杯，遠方可見橋與建築。", ["傷心難過", "失去", "只看到事情的一面", "仍保有部分"], "失去與尚存同時可見；先承認失落，再檢查未倒下的資源。", "關係可指分手或離開帶來的痛苦；工作可指只看缺點而忽略仍有的優勢。"],
    "cups_six" => ["較高大的人把盛花聖杯交給較小的人，背景有村落與孩童般的姿態。", ["不平等的關係", "深度的承諾", "回憶", "真誠的愛"], "照顧者與被照顧者的角色不對稱，回憶也可能成為現在的資源或依賴。", "關係可指過去連結或照顧模式；工作可指由經驗與舊方法處理問題。"],
    "cups_seven" => ["人物面對雲中浮現的七只杯子，杯中物各異，中間有被布遮住的發光人物。", ["夢境", "自己的想像", "各種的慾望", "不了解自己"], "候選很多但不等於都真實；需要把想像、慾望和可驗證的選項分開。", "工作可指標準未定、選擇太多；關係可指投射或對對方想像過多。"],
    "cups_eight" => ["人物背對地面排列的八只杯子，向山路與月亮方向離開。", ["缺乏", "離開去尋找", "實質的行動力", "改變現狀"], "既有局面已不能滿足，離開是有意識的選擇；新方向仍有未知。", "工作可指離開不滿意的工作；關係可指離開舊模式或尋找新關係。"],
    "cups_nine" => ["人物坐在高台前，九只杯子排列展示，姿態面向前方。", ["豐富的成就", "滿意", "炫耀", "不肯分享"], "成就與滿足可被享受，但分享與否會改變關係中的意義。", "工作可指享受成果；關係可指滿意但可能自我中心。"],
    "cups_ten" => ["十只聖杯形成彩虹，兩人張開雙臂，孩子在旁跳舞，背景有房屋與景色。", ["感情的完滿", "希望", "和樂的氣氛", "如家人的相處模式"], "完滿被表現為共同生活與穩定互動，不只是一時激情；希望仍需現實維持。", "關係可指家庭式穩定；工作可指團隊和諧或想要的未來圖像。"],
    "swords_ace" => ["雲中手握劍，劍尖有王冠與植物；兩側有棕櫚與橄欖枝。", ["挑戰", "主動出擊", "榮耀與勝利", "過度"], "新的挑戰要求清楚思考與正面迎戰；勝利與過度使用力量是同一把劍的兩面。", "工作可指正面處理問題；關係可指直接溝通，但需避免過度。"],
    "swords_two" => ["蒙眼人物坐在海岸，兩手交叉各持一劍，月亮在上方。", ["逃避", "沒有行動", "自我防禦", "僵持"], "信息或選擇被封在胸前；等待本身不會改變局面，兩股力量仍在拉扯。", "工作可指協商前的僵持；關係可指防衛與冷戰。"],
    "swords_three" => ["三把劍穿過心形，背景有雨與烏雲。", ["心碎和憂鬱", "淨化和成長的眼淚", "缺乏及不完善", "延遲"], "痛苦被明確看見，也可能迫使情緒與問題被說清楚；不要用成長掩蓋傷害。", "工作可指關鍵因素缺失造成延誤；關係可指受傷或分離。"],
    "swords_four" => ["人物躺在教堂中休息，牆上有三把劍，身旁一把，窗外有彩色玻璃。", ["避難與休息", "沉思", "外來的威脅", "未來的戰爭"], "退離衝突提供恢復與思考，但安全位置不等於外部風險永遠消失。", "工作可指暫停或換環境；關係可指需要空間後再處理問題。"],
    "swords_five" => ["人物手持兩把劍，地面有三把劍，離去的兩人低頭，天空有雲。", ["得意", "爭執", "只有一方勝利", "一時爭勝並無收穫"], "局部勝利伴隨關係代價；把對抗當成唯一方法會削弱後續合作。", "工作可指權力衝突；關係可指爭吵中有人暫時佔上風但沒有建設性。"],
    "swords_six" => ["小船載著一人與兩名乘客，船夫持長竿，六把劍插在船中，船朝向遠方。", ["療傷的行動", "低調", "內心的傷痛", "行動上的幫助"], "離開受傷處需要實際過渡與外部協助；低調不代表問題已消失。", "工作可指調職或低調處理；關係可指帶著傷痛離開並尋求支持。"],
    "swords_seven" => ["人物從營地帶走五把劍，兩把留在身後，動作避開正面衝突。", ["趁虛而入", "信心", "欺騙或偷竊", "不可能的任務"], "行動依賴隱蔽或非正面手段；需檢查信息是否足夠、任務是否超出能力。", "工作可指繞過防備或信息不透明；關係可指隱瞞與不直接面對。"],
    "swords_eight" => ["蒙眼人物被布帶與八把劍圍住，地面泥濘，遠處有建築。", ["綑綁", "看不見真相", "被敵意包圍", "壞消息"], "限制感與盲點讓行動變窄；需要區分外部約束和自己的視野限制。", "工作可指被流程或多方意見牽制；關係可指防衛與溝通受阻。"],
    "swords_nine" => ["人物坐在床上掩面，背後九把劍水平排列，床面有圖案。", ["焦慮及害怕", "惡夢一場", "逃避現實", "無能為力"], "夜間反覆的擔憂放大無力感；必須把想像的災難和現實證據分開。", "工作可指把改變視為無法承受；關係可指反覆恐懼與逃避對話。"],
    "swords_ten" => ["人物伏倒在海岸，十把劍插在背上，遠方海面有一道日光。", ["孤獨寂寞", "極大的痛苦", "死亡與結束", "即將有重大轉變"], "一個方式或階段已到盡頭，痛苦需被承認；遠方的光只表示可見的轉向，不保證結果。", "工作可指不可持續的局面結束；關係可指孤立或關係方向的終止。"],
    "pentacles_ace" => ["雲中手托出一枚錢幣，前方有花園小徑、拱門與遠山。", ["具體的成果", "物質的享受", "目前的方向", "未來的可能性"], "可掌握的資源或成果已出現；清楚方向仍要透過實際工作落地。", "財務可指新資源或物質機會；工作可指具體而可執行的開始。"],
    "pentacles_two" => ["人物手持兩枚錢幣，錢幣由環形帶相連；後方海面有船。", ["進與出的流動", "不同選擇的衡量", "波動起伏", "有賺有賠"], "資源與選擇在動態平衡中；需要觀察週期，不把短期波動當成確定結果。", "工作可指重新分配或輪調；關係可指在兩個需要之間搖擺。"],
    "pentacles_three" => ["教堂中有僧侶、設計師與工匠，三枚錢幣嵌在拱門上，人物分工合作。", ["專業上共同協力", "兼顧各種需要", "長久保值", "穩固的基礎"], "成果依賴不同專業與標準協作；長期價值比單人短期控制更重要。", "工作可指專業團隊與分工；關係可指共同建立穩定基礎。"],
    "pentacles_four" => ["人物坐著抱住錢幣，頭頂一枚、腳下兩枚，身體把資源包住，背景有城市。", ["不安全感", "極度重視金錢", "控制的慾望", "累積及增值"], "資源帶來安全感也可能變成守住與控制；需要分辨保護和封閉。", "工作可指守住收入或預算；關係可指因不安全而控制對方。"],
    "pentacles_five" => ["兩人走過有五枚錢幣圖案的彩窗，人物衣著單薄並扶杖前行。", ["表面的華麗", "財務上的窘困", "受傷", "失去能力"], "外在資源與身體處境都顯得不足；不要只從表面判斷誰有支援。", "財務可指資源不足；工作可指被忽略或受傷後仍要找實際援助。"],
    "pentacles_six" => ["六枚錢幣懸在富商頭上；他手持秤，向兩名跪著的人分配錢幣。", ["地位上的不平等", "計算與衡量", "慈悲心", "以金錢控制對方"], "給予與接受受權力、秤和條件限制；援助可能同時含有控制。", "工作可指資源分配與權力差；關係可指一方提供但要求回報。"],
    "pentacles_seven" => ["農夫靠著杖看向結滿七枚錢幣的樹，人物停在收成前。", ["努力的初步成果", "收成及交易", "思考下一步", "新的創意"], "已有可見成果但尚未完成；需要評估是否收割、交換或改變方法。", "工作可指計畫累積與評估；關係可指已有投入但要重新思考方向。"],
    "pentacles_eight" => ["工匠坐在板凳上雕刻錢幣，後方的竪直木面上排列錢幣，地上還有未完成的工作。", ["專注", "成熟的技術", "工作才有成果", "持續努力"], "能力由重複、專注和持續工作形成；未完成部分要求耐心而非捷徑。", "工作可指技能提升或穩定產出；關係可指用持續行動維護品質。"],
    "pentacles_nine" => ["人物穿華麗衣服走在葡萄園，周圍有九枚錢幣，一隻鳥停在手上。", ["悠閒", "富裕", "謹慎", "小心保護理想"], "成果帶來自主與享受，但仍要謹慎維護已有資源，不必把獨立等同於孤立。", "工作可指獨立成果與成熟收穫；關係可指享受自己的生活後再選擇互動。"],
    "pentacles_ten" => ["拱門下有四名人物與兩隻狗，十枚錢幣排成生命之樹般的結構，背景是居所與家族場景。", ["各種角色", "集體的富裕", "用錢得當", "實踐與完成"], "資源在家庭、傳統與多個角色間流動；完整性要靠實際安排而非只靠擁有。", "工作可指家族或團隊資源；關係可指多代或多角色共同生活與責任。"],
    "wands_page" => ["年輕人物側身持杖，遠方是山地，人物停下看向杖。", ["天真純潔", "惡作劇", "行動的訊息", "嘗試錯誤"], "新消息或新嘗試帶來熱情，也可能因不成熟而需要直接修正。", "工作可指新任務或學習；關係可指以簡單直接方式傳遞新訊息。"],
    "wands_knight" => ["騎士騎馬持杖，馬匹向前，人物與杖都呈現動勢。", ["勇於面對挑戰", "行動力", "樂觀", "質樸率真"], "速度與勇氣推動局面，但過度行動會忽略條件；要把目標說清楚。", "工作可指主動出擊與旅行；關係可指需要新鮮行動。"],
    "wands_queen" => ["王后坐在王座上持杖，旁有向日葵與黑貓，畫面集中在她的可見 presence。", ["光明而愉快", "親切", "善用直覺", "財運的提升"], "溫暖、可見的影響力與直覺可以帶動他人；也要防止以魅力取代真實互動。", "工作可指帶動團隊或創意；關係可指以正面而互相尊重的方式互動。"],
    "wands_king" => ["國王坐在王座上持杖，背景有沙漠與蜥蜴，姿態穩定而直視前方。", ["經驗豐富", "謀定而後動", "創造力", "固執己見"], "經驗與遠見能把問題轉成新方法；等待資訊與適時決定比即時反應更穩。", "工作可指成熟領導與創新；關係可指穩定但可能固執的主導。"],
    "cups_page" => ["年輕人物持杯站在水邊，杯中有魚，人物注視杯中訊息。", ["好奇心", "好學不倦", "想像力", "人際關係的新訊息"], "情緒或關係的新訊息需要好奇與學習；想像力仍須回到實際互動。", "工作可指學習新方法；關係可指出現新訊息或新的友誼入口。"],
    "cups_knight" => ["騎士持杯騎馬，馬匹朝前，背景有水面與山地。", ["溫柔浪漫", "傳播理念", "朋友來訪", "提出建議"], "理想與表達帶來靠近，但需要用現實角度檢查浪漫敘事。", "工作可指提出意見或創意；關係可指溫柔靠近與朋友消息。"],
    "cups_queen" => ["王后坐在水邊王座，雙手捧著華麗聖杯，周圍有水與植物。", ["慈愛關懷", "同理心", "靈性上的成長", "保持專注"], "感受與同理能協助理解他人，但仍需保持邊界與對現實的專注。", "工作可指用同理處理關係；感情可指照顧與情緒理解。"],
    "cups_king" => ["國王坐在水面上的王座，手持杯與權杖，周圍有水流與船。", ["處變不驚", "慈悲寬容", "學識豐富", "重視婚姻及家庭"], "情緒穩定和寬容支持領導與家庭責任；穩定不等於壓抑或不表達。", "工作可指成熟的協調與領導；關係可指包容、家庭和穩定承擔。"],
    "swords_page" => ["年輕人物持劍站在風中，身體警覺，周圍雲與高地開闊。", ["輕率", "裝模作樣", "刺探別人隱私", "挑戰的新訊息"], "好奇與警覺帶來信息，也可能變成八卦或未經證實的判斷。", "工作可指新問題與調查；關係可指需要小心分享與核對。"],
    "swords_knight" => ["騎士持劍騎馬急速前進，背景有風與雲，方向明確。", ["豪爽", "急躁易怒", "強制手段", "戰利品"], "直奔問題能推進局面，也可能在沒有溝通時變成強制；速度需要目標與邊界。", "工作可指果斷處理；關係可指衝突升高或直接對話。"],
    "swords_queen" => ["王后坐在王座上持劍，另一手伸出，姿態清楚而有距離。", ["沉著冷靜", "一擊必殺", "異性緣不佳", "思考感情問題"], "清晰界線與理性判斷可避免重複傷害；過度切斷感受會失去真正連結。", "工作可指公事公辦；關係可指保持界線、不用混亂關係免責。"],
    "swords_king" => ["國王持劍坐在王座上，姿態端正，背景有雲與樹。", ["清晰的判斷力", "公平客觀", "領導統御", "向專家求教"], "把情緒與事實分開，用公正標準治理；需要時承認專業限制並尋求意見。", "工作可指決策與治理；關係可指公平分工和清楚表達。"],
    "pentacles_page" => ["年輕人物站在草地持錢幣，注視手中的錢幣；身後可見地景。", ["務實的觀察", "學以致用", "財務上的新訊息", "少年老成"], "小心觀察與學習可把新資源變成能力；不要只停在收集信息。", "工作可指學習財務或技能；關係可指以實際行動回應。"],
    "pentacles_knight" => ["騎士停在馬上持錢幣，馬匹與人物都較穩定，背景是耕地。", ["努力工作賺錢", "負責任", "實用主義", "不解風情而且沒有情調"], "可靠的持續投入能完成任務；但若只看效率，會忽略關係和彈性。", "工作可指穩定執行；關係可指責任感強但互動缺少情感。"],
    "pentacles_queen" => ["王后坐在樹下的花園中抱著錢幣，周圍有植物與小動物。", ["精打細算", "照顧", "服務他人", "長期利益"], "照顧資源與他人需要長期投入；慷慨不能取代界線與自我照顧。", "工作可指管理資源和照顧團隊；關係可指實際照顧與長期承諾。"],
    "pentacles_king" => ["國王坐在充滿植物與錢幣的王座，手持錢幣，周圍有葡萄與建築。", ["有效率地用錢", "良好的財務基礎", "常識豐富", "重視生活享受"], "資源治理、常識與生活品質需要一起被管理；穩定不是停止改進。", "工作可指有效治理與成果；關係可指物質保障與生活品質。"],
    "magician" => ["人物一手指天一手指地，桌上放著四種花色物件，頭頂有無限符號。", ["新開始", "自信", "主動性", "條件完備"], "集中注意力、工具與手勢把意念轉成可操作的現實；技巧也可能被誤用。", "工作可指把資源組合成方案；關係可指主動溝通，但需核對是否操弄。"],
    "high_priestess" => ["女性坐在黑白柱間，身後有帷幕，手上有卷軸，畫面強調等待與內在知識。", ["靜默", "尚未完全顯現", "平衡二元對立", "智慧"], "答案尚未完全外顯；靜待與觀察比立即揭露更符合頁面敘事。", "工作可指尚未公開的信息；關係可指保留與需要時間建立信任。"],
    "empress" => ["女性坐在自然與麥田中，旁有盾牌與水流，畫面有豐饒與生長。", ["未開發的", "肥沃多產", "享樂", "愛與美"], "照顧、培育與實際資源支持生長；不要把滋養直接等同於無限付出。", "工作可指培養產品或團隊；關係可指照顧與穩定的創造。"],
    "emperor" => ["人物坐在有公羊頭王座上，手持權杖，背景有石山與城堡。", ["權力", "慈愛保護", "執行力", "意志力"], "規則與結構提供保護也可能壓縮彈性；權力要以可執行責任證明。", "工作可指制度與領導；關係可指責任和穩定但可能過度控制。"],
    "hierophant" => ["宗教人物坐在兩柱間，面前有兩名跪者，腳下有交叉鑰匙與階梯。", ["靈性成長", "慈悲", "組織的秩序", "貴人相助"], "知識、傳統和制度提供共同語言，也要求檢查規範是否仍適用。", "工作可指師徒或制度流程；關係可指共同價值也可指規範壓力。"],
    "lovers" => ["天使在山上看著裸體男女，兩側有樹與蛇，人物位於同一景觀中。", ["純真", "兩情相悅", "引誘", "選擇"], "選擇同時涉及吸引、價值與後果；不能只把牌面收斂為浪漫關係。", "工作可指價值一致與合作選擇；關係可指承諾與成熟的取捨。"],
    "chariot" => ["人物位於戰車內，前方有兩隻不同顏色的人面獅身像；人物雙臂位於身前。", ["戰爭行為", "不斷努力", "征服", "以智取勝"], "不同力量需被一個方向統整；外在勝利不能取代對內在牽引的控制。", "工作可指目標導向推進；關係可指共同方向或控制衝突。"],
    "strength" => ["女子以親昵、柔和而堅定的動作控制獅子口部；頭上有無限符號，身旁有花環。", ["權力", "勇氣", "相互配合", "以柔克剛"], "力量以耐性和接觸被引導，而不只靠壓制；柔和不代表沒有邊界。", "工作可指處理強烈情勢；關係可指以耐心而非強迫互動。"],
    "hermit" => ["披斗篷的人站在山頂持燈與手杖，向下看著遠方。", ["離群索居", "老朽", "謹慎", "引導與教育"], "退離人群提供檢查與引導；孤獨需服務於理解而不是逃避。", "工作可指專注研究或尋求導師；關係可指需要空間與清楚內在方向。"],
    "wheel_of_fortune" => ["中央有四臂輪盤，周圍有蛇、獅身人面像與人物，輪子處於運動。", ["命中註定", "幸運", "無可選擇的改變", "處變不驚"], "變化帶來新條件，能做的是辨識可控範圍與適時調整。", "工作可指外部周期改變；關係可指情勢轉換而非必然結果。"],
    "justice" => ["人物坐在王座，右手持劍、左手持秤，兩側有帷幕。", ["公平正義", "平衡", "重要決定", "以法律解決"], "事實、標準與後果需要被同時衡量；清楚判斷仍需可執行責任。", "工作可指制度與評估；關係可指分工、公平與承認結果。"],
    "hanged_man" => ["人物倒掛在樹上，一腳被綁，頭部周圍有光，姿勢固定而安靜。", ["懸而未決", "考驗", "洞悉的能力", "犧牲"], "被迫或選擇暫停使視角改變；不要把停滯自動解釋成靈性進步。", "工作可指暫停計畫以重新看問題；關係可指放下控制或等待。"],
    "death" => ["骷髏騎士騎白馬，前方有倒下人物，遠方有雙塔與升起的太陽。", ["必死的命運", "重大的轉變", "結束與開始", "解脫"], "結束與新的開端同時存在，但需先承認不可逆的舊局面已終止。", "工作可指階段轉換；關係可指舊模式結束，不等於預告死亡。"],
    "temperance" => ["有翼人物一腳在水一腳在地，將水在兩杯間調和，遠處有道路與山。", ["相互融合", "轉化與淨化", "中庸之道", "管理與調控"], "不同意見與資源可被調和，但需要持續調節而非一次完成。", "工作可指跨方協作；關係可指協調需求與節奏。"],
    "devil" => ["有角人物坐在黑色座台，男女被鏈子連住，火焰在背景。", ["毀壞", "暴力相向", "被慾望蒙蔽", "短暫的享樂"], "吸引與束縛同時可見；需要檢查實際權力與選擇，而不是把人定罪。", "工作可指依賴或控制結構；關係可指欲望與界線問題。"],
    "tower" => ["閃電擊中高塔，王冠落下，兩個人物從塔上墜落，背景是黑雲。", ["被毀滅", "突來的意外", "自作自受", "執迷不悟"], "被擊中的結構不能再維持原樣；是否形成可用的重建，要由其他牌與現實檢查。", "工作可指制度被打斷；關係可指突然揭露或舊模式崩解。"],
    "star" => ["裸身人物在水邊倒水，天空有一大星與七小星，樹上停著鳥。", ["目標和希望", "想得美", "分享與回饋", "渴望自由"], "穩定的方向感和持續回饋支持恢復；希望仍要通過實際投入。", "工作可指長期願景；關係可指開放交流與逐步恢復信任。"],
    "moon" => ["月亮在兩座塔上方，兩隻站立動物分別位於塔前，甲殼類動物從水中伸出，遠處有小路。", ["不安與恐懼", "欺騙和幻覺", "隱藏的危險", "難以捉摸的變化"], "信息不全與直覺反應同時存在；需要等待更多可核對的線索。", "工作可指不確定與誤解；關係可指投射、恐懼或未說出的內容。"],
    "sun" => ["太陽上方照耀，孩子騎白馬並手持旗幟，背景有圍牆與花朵。", ["圓滿成功", "快樂與滿足", "一視同仁", "朝向光明面"], "可見度、活力與清楚表達支持共同成果；公開也帶來責任。", "工作可指成果被看見；關係可指坦白、歡樂與可共享的生活。"],
    "judgement" => ["天使吹響號角，棺木中的人物起身，遠方有山與水。", ["復活與重生", "作判斷", "覺醒", "結算成果"], "新的召喚要求回看過去並作出回應；不是自动赦免，也不是命定事件。", "工作可指重新評估與回到使命；關係可指重新對話或接受歷史。"],
    "fool" => ["人物站在懸崖邊向前，肩上小包，手持白花，身旁有狗與高山。", ["明顯的危險", "無知", "放縱的愚行", "無限的可能性"], "輕裝出發保留多種可能，但前進仍需要看見腳下的風險與現實。", "工作可指新旅程；關係可指開放嘗試但不保證穩定。"],
    "world" => ["人物在花環中舞動，四角有一個人形頭像、鷹頭、牛頭、獅頭，手持兩根杖。", ["自然的規律", "到此為止", "完美的結局", "統合"], "作者把完成寫成到此為止：各種元素已統合並維持穩定，不把它推演成必然轉變。", "工作可指完成、整合與維持現狀；關係可指共享的完成感與穩定，不必虛構新的轉折。"]
  }.freeze

  DAWN = {
    "cups_king" => ["聖杯國王", "King", "水", "黑帝斯／冥界之王", ["能在高度情緒中保持穩定", "洞察與慈悲並存", "以照顧與影響力領導"], ["操縱或情緒投射", "沉浸而不說清楚", "把家庭責任變成控制"], ["在壓力中調停", "先理解再決策", "對家人或團隊保持穩定承擔"], ["照顧與深度連結", "對情緒和轉化議題敏感"], ["影響他人的領導、照護、心理或水域相關工作"], "用可觀察的穩定、照顧和邊界檢查原型；不以性別或身份收斂"],
    "cups_queen" => ["聖杯王后", "Queen", "水", "神祕主義者／女祭司和通靈人", ["直覺與同理", "療癒與人道關懷", "不需多語言也能理解"], ["玻璃心、操縱、脫離現實", "過度吸收他人情緒", "冷酷利用弱點"], ["辨認自己的感受與他人感受", "在關懷中維持界線", "用傾聽協助而非代替他人決定"], ["需要情緒安全與深層理解", "可能把照顧和依賴混在一起"], ["諮商、照護、助人、社群支持"], "原型只在行為、位置和關係 evidence 支持時使用"],
    "cups_knight" => ["聖杯騎士", "Knight", "水", "浪漫情聖", ["理想主義、表達和創意", "主動靠近", "用情感推動行動"], ["把幻想當事實", "追逐新鮮感", "逃避承諾或情緒誇張"], ["把感受說出來", "把靈感轉成具體邀請或行動", "檢查浪漫敘事的現實條件"], ["吸引與投射並存", "需要區分熱情和持續承諾"], ["藝術、溝通、創意或需要情感表達的角色"], "浪漫不是對方身份證，也不證明關係結果"],
    "cups_page" => ["聖杯侍者", "Page", "水", "共感人", ["敏感、想像力和情感開放", "能接收細微訊息", "以創作或照顧表達"], ["情緒過載、依賴、難以分辨自己的需要", "把錯誤歸給別人", "逃避直接表達"], ["先辨認情緒來源", "用創作或明確語言表達需要", "在關係中保持自己的空間"], ["可能指學習情感溝通或相互依賴模式", "不可直接推定年齡或性格"], ["藝術、照護、創意、需要同理的工作"], "以行為和邊界判斷，不以敏感標籤定人"],
    "wands_king" => ["權杖國王", "King", "火", "企業家", ["願景、勇氣和影響力", "主動創造方向", "鼓勵他人發揮潛力"], ["自我膨脹、利用他人", "頻繁改變、殘酷或只看效用", "把家人或團隊納入控制"], ["聚焦真正熱情", "承擔領導的後果", "把遠見轉成可執行的共同方向"], ["關係需要容納其可見度與雄心", "不能用職業或性別認定身份"], ["創業、領導、公共影響或創意事業"], "用影響力的實際行為測試企業家原型"],
    "wands_queen" => ["權杖王后", "Queen", "火", "表演者", ["魅力、創意和表達", "鼓勵並聚集他人", "對自己的影響力有意識"], ["過度自戀、情緒誇張", "焦慮與防衛", "以表面形象遮蓋真實需要"], ["找到自己的表達方式", "在被看見與獨立間平衡", "把魅力轉成共同工作"], ["關係中既需要關注也需要自主空間", "不等於明星或特定性別"], ["藝術、社交、創業、需要說服或聚眾的角色"], "原型需由可見表達和對他人的實際影響支持"],
    "wands_knight" => ["權杖騎士", "Knight", "火", "冒險家", ["移動、旅行、勇氣和主動", "面對變化適應快", "把人帶向新經驗"], ["自私、粗心、不成熟", "不定下來、永遠不滿", "把承諾當束縛"], ["選擇一個真正熱愛的方向後行動", "把冒險拆成可承擔的步驟", "為速度建立邊界"], ["可能是短期熱情而非長期關係", "不把旅行或自由直接讀成逃避"], ["旅行、教育、創意、需要變化和問題解決的工作"], "以持續行動和承諾能力區分冒險與逃離"],
    "wands_page" => ["權杖侍者", "Page", "火", "彼得潘", ["好奇、快樂、能量和新嘗試", "把氣氛活化", "學習文化與科技變化"], ["不想長大、爭辯、八卦", "遇到困難就退出", "用戲劇化取代責任"], ["把好奇放在有創意的事情", "承認錯誤並繼續學習", "用明確訊息而非噪音推進"], ["可以是自我面向或新訊息入口", "不以年齡或外貌定義"], ["學習、內容、創意、需要活力的入口角色"], "先看行動與學習，不把 Peter Pan 當現實身份"],
    "pentacles_king" => ["錢幣國王", "King", "土", "總經理", ["治理資源、穩定和責任", "有系統地作決策", "提供物質保障"], ["貪婪、批判、壓抑感情", "固守而不改變", "以金錢取得尊重或控制"], ["列出風險與盲點", "用可行的資源方案承擔責任", "讓生活品質與效率並存"], ["物質能力不是道德或身份證明", "不可直接推定有錢或職位"], ["治理、財務、企業管理、資源配置"], "要求現實資源與可交付責任同時可見"],
    "pentacles_queen" => ["錢幣王后", "Queen", "土", "療癒者", ["照顧、耐心、資源實作", "把社群與生活維持住", "在危機中可靠"], ["上帝情結、操縱、傲慢", "只在被需要時感到有價值", "忽略自己的需要"], ["辨認需要被照顧的地方", "向社群求助也接受支持", "把照顧轉成可持續安排"], ["關懷不是無限責任", "不把醫療/照護原型當診斷"], ["照護、健康服務、社群、資源改善"], "以可觀察照顧與資源行動核對療癒者候選"],
    "pentacles_knight" => ["錢幣騎士", "Knight", "土", "軍人", ["忠誠、紀律、責任與耐力", "完成長期任務", "保護和服務團體"], ["僵硬、完美主義、要求他人服從", "只看規則與效率", "把工作身份當成全部自我"], ["拆分任務並逐件完成", "確認結構和目標仍適用", "以持續服務而非口號證明承諾"], ["穩定可能變成停滯", "不以制服、性別或職業認定人物"], ["長期專案、服務、組織和流程工作"], "用持續負責的行動區分可靠與僵化"],
    "pentacles_page" => ["錢幣侍者", "Page", "土", "自然主義者", ["觀察、耐心、實作和自然連結", "讓事情按合理速度成熟", "非語言的照顧"], ["界線不清、孤立、沉浸自己的世界", "拖延或拒絕溝通", "把不合群誤當成免責"], ["先看簡單可做的下一步", "允許學習和成熟需要時間", "用清楚的生活安排保護空間"], ["自然連結是作者候選，不證明物種或性格", "不以年齡或衣著認定"], ["環境、動物、手作、需要耐心的工作"], "以實際節奏和邊界判斷是否適用"],
    "swords_king" => ["寶劍國王", "King", "風", "科學家／專家", ["宏觀、理性、精準和專業", "把複雜問題組織成模型", "以知識推動改變"], ["冷漠、自大、過度理性", "逃離生活細節", "把理想當作凌駕他人的權力"], ["重新檢查細節與盲點", "向專業求教也保持可理解", "把遠見變成可共享的決策"], ["專業不是身份證明，也不是醫療/法律結論", "理性需與人和現實接觸"], ["研究、工程、教育、政策和專業治理"], "需有問題解決或專業行為 evidence，不能因聰明標籤套用"],
    "swords_queen" => ["寶劍王后", "Queen", "風", "裁判者", ["公平、直率、清晰和談判", "看穿動機並守口如瓶", "把混亂說成可處理的問題"], ["殘酷、批判、操縱", "切斷感受", "用聰明逃避脆弱"], ["問何種結果公平", "清楚溝通並保留開放觀點", "把邊界和同理一起使用"], ["不等於冷酷或單身身份", "只有行為支持時才讀成裁判角色"], ["談判、管理、公共溝通、需要判斷的角色"], "以語言、界線與公正行動核對原型"],
    "swords_knight" => ["寶劍騎士", "Knight", "風", "戰士", ["迅速、強力、勇於行動", "守護弱者", "按自己的準則面對挑戰"], ["不理性、易怒、倉促處罰", "被別人利用", "復仇和不計後果"], ["把恐懼轉為具體行動", "先確認任務和出口", "用行動而不是旁觀推進"], ["守護者不自動等於暴力", "要有現實危險或衝突 evidence 才能收斂"], ["危機處理、倡議、行動導向的工作"], "只在實際保護/推進行為支持時使用戰士"],
    "swords_page" => ["寶劍侍者", "Page", "風", "偵探", ["觀察、提問、探索和溝通", "從細節找出模式", "願意質疑複雜說法"], ["幼稚、算計、背刺、不被信任", "困在自己的思考", "把懷疑變成監控"], ["做好功課並提出可核對的問題", "把信息整理成簡單線索", "用批判性思考而非盲信"], ["偵探是作者原型，不證明犯罪或欺騙", "需要行為和位置支持"], ["研究、調查、分析、解題和溝通"], "以問題和證據行動判斷，不以好奇等同不信任"]
  }.freeze

  RANKS = {
    "Page" => ["溝通／學習／消息入口", "先問信息是否正在進入、被學習或需要被說清楚；不是年齡證明。"],
    "Knight" => ["行動／推進", "先問什麼正在移動、被推進或需要承擔速度；不是道德等級。"],
    "Queen" => ["照顧／影響／關係維持", "先問誰在維持、照顧、影響或調節關係；不是性別身份。"],
    "King" => ["領導／責任／資源治理", "先問誰在承擔決策、責任或資源配置；不是职位证明。"]
  }.freeze

  # Card-specific condensed evidence manually checked against the rendered
  # Nichols chapter pages listed below. These are author-level amplifications,
  # not replacements for the Phase 4C RWS visual packet.
  NICHOLS_DETAILS = {
    "fool" => {
      "transferable_method" => "把无固定编号、带着包袱走向边缘的旅人作为不确定性与选择的 motif，先检查现实中的自由是否也包含可见风险。",
      "author_specific_amplification" => "Nichols 将愚人写成穿行于秩序之间的 Joker/Trickster：他的含混同时容纳创造与破坏，不能被一个固定性格标签钉死。",
      "deck_specific_material" => "Nichols 比较 Marseille 愚人的行走姿态、狗与悬崖等图像；这些比较只作为作者材料，不改变当前 RWS packet 的可见事实。",
      "polarity" => "自由旅行／打破既有秩序 与 无知、危险和破坏并存。",
      "alternative" => "若问题中的行为已有清楚计划与护栏，愚人 amplification 可能只提示开放尝试，而不支持鲁莽行动。",
      "projection_warning" => "不要把自己对冒险者、年轻人或 Joker 的联想投射成当事人的身份或动机。",
      "evidence_bridge" => "visible edge-and-travel motif → hold creation/destruction polarity → test whether the real choice has safeguards",
      "source_pages" => [49, 60, 78]
    },
    "magician" => {
      "transferable_method" => "把桌面前被集中使用的工具与人物的停驻联系起来，检验意图是否已经转成可控制的操作。",
      "author_specific_amplification" => "Nichols 将魔术师区别于四处游走的愚人：他暂时停驻，把能量集中到面前的对象，成为 Creator 与 Trickster 的双重角色。",
      "deck_specific_material" => "章节以魔杖、桌面和 Hermes/Mercurius 的比较扩展图像；比较性牌组材料不能覆写 RWS 视觉事实。",
      "polarity" => "创造、集中与自我实现的能力／表演、操弄或把控制误当成创造。",
      "alternative" => "若现实材料只显示准备而没有可观察的执行，较弱的读法是资源已到位但尚未转成行动。",
      "projection_warning" => "不要因为牌面工具或表达力，就把当事人认定为有魔法、专业资格或操纵他人的人。",
      "evidence_bridge" => "visible focused operator motif → distinguish directed agency from performance → test against actual execution",
      "source_pages" => [79, 90]
    },
    "high_priestess" => {
      "transferable_method" => "把被帷幕后方、柱间或门槛隔开的信息当作暂时不可公开的层面，检查问题是否需要等待与辨识，而非立即行动。",
      "author_specific_amplification" => "Nichols 以 Popess 的神秘来源和 Pope Joan 传说放大‘隐藏但有创造力的知识’；随后用 Astarte 作为原始女性原则与月亮节律、繁衍及生长／衰败的作者性放大；这不是 RWS 人物身份。",
      "deck_specific_material" => "第119页正文以 Astarte 说明原始女性原则、月亮节律、繁衍及生长／衰败，第120页图注标识作者选用的 Astarte 雕像；这些不是 RWS 人物身份或视觉事实的证明。",
      "polarity" => "内在知觉、等待与潜藏知识／秘密、隔绝和把未知浪漫化。",
      "alternative" => "若牌位要求公开沟通且现实已有明确资料，这一 amplification 可退为先整理信息，而不是继续隐藏。",
      "projection_warning" => "不要把安静、女性化或神秘的视觉直接投射成当事人的性别、灵性能力或秘密。",
      "evidence_bridge" => "visible threshold-and-withheld-information motif → preserve ambiguity → test what can actually be known now",
      "source_pages" => [112, 119, 120],
      "source_page_support" => {
        "112" => "章节开头建立 Popess／High Priestess 的门槛与暂时保留知识 motif。",
        "119" => "正文明确以 Astarte 放大原始女性原则、月亮节律、繁衍及生长／衰败，并将其与 Popess 的血脉和创造性知识联系起来。",
        "120" => "图注明确标识第119页正文所引用的 Astarte 雕像；本页仅作为作者选定的插图证据，不被当作 RWS 女祭司身份或视觉事实。"
      }
    },
    "empress" => {
      "transferable_method" => "从丰饶、身体性和可见照料的 motif 出发，检查现实中是否有让事物生长的资源与容纳空间。",
      "author_specific_amplification" => "Nichols 把皇后写成 Madonna/Great Mother 与天地相接的力量：她不只是柔和照顾，也把精神与物质联结起来。",
      "deck_specific_material" => "作者比较皇后、金色权杖、鹰和其他牌组的母性图像；这些扩展不可当作 RWS 额外物件。",
      "polarity" => "滋养、生成与容纳／过度保护、沉溺或让增长失去边界。",
      "alternative" => "若现实没有可持续资源，较窄的读法是需要照料的需求被看见，而不是已经拥有丰盛成果。",
      "projection_warning" => "不要把皇后当作母亲身份、女性身份或怀孕事实的证明。",
      "evidence_bridge" => "visible growth-and-nurture motif → ask what sustains growth → test resources and boundaries",
      "source_pages" => [131, 140]
    },
    "emperor" => {
      "transferable_method" => "从边界、结构与可通行路径的 motif 出发，检查现实是否需要明确规则、责任和能执行的基础设施。",
      "author_specific_amplification" => "Nichols 将皇帝写成文明之父：他为皇后的花园划出路径、房屋与城市，把自然能量组织成共同生活的秩序。",
      "deck_specific_material" => "章节的父权、文明和历史图像是作者扩展材料，不证明现实中的父亲、男性或统治者身份。",
      "polarity" => "结构、保护与公共责任／僵硬、外在权威和以秩序压过个体需要。",
      "alternative" => "若问题已有过度规则，皇帝 amplification 可能改变为重建可用边界，而不是增加控制。",
      "projection_warning" => "不要把坐在王座、胡须或男性化图像直接当作职位、父亲身份或支配动机。",
      "evidence_bridge" => "visible boundary-and-structure motif → distinguish infrastructure from control → test responsibility in behavior",
      "source_pages" => [152, 160]
    },
    "hierophant" => {
      "transferable_method" => "当牌面出现中心教导者与受教者结构时，检查知识是被传递、被制度化，还是被动接受。",
      "author_specific_amplification" => "Nichols 强调教皇首次把多个普通人带进牌面：他成为可见的神圣中介，问题转向共同仪式、信念与权威如何影响人。",
      "deck_specific_material" => "作者的宗教图像、教会历史和其他牌组比较只保留为解释素材，不成为现实宗教身份证据。",
      "polarity" => "共同学习、传统与意义中介／服从、教条和把权威交出。",
      "alternative" => "若现实没有稳定机构，可能只是在寻找可用的老师或共同语言，而非加入某个体系。",
      "projection_warning" => "不要从教皇牌推断真实宗教、牧师身份或道德优越。",
      "evidence_bridge" => "visible teacher-and-students motif → inspect authority and learning relation → test whether guidance is reciprocal",
      "source_pages" => [173, 180]
    },
    "lovers" => {
      "transferable_method" => "从两人、第三方力量与选择张力的 motif 出发，检查欲望是否已经变成需要承担后果的决定。",
      "author_specific_amplification" => "Nichols 把恋人写成 Cupid 的金色错误：吸引力与三角关系能把选择理想化，使人忽略社会压力和现实承诺。",
      "deck_specific_material" => "章节使用 Cupid、伊甸园和其他牌组的三角图像作比较；这些不是 RWS 关系事件的直接证据。",
      "polarity" => "亲密、真实选择与联结／诱惑、投射和让欲望替代判断。",
      "alternative" => "若现实已有清楚承诺，较弱的替代解释是价值排序，而不是第三者或秘密关系。",
      "projection_warning" => "不要把天使、裸体或两人图像当成恋爱对象、出轨或婚姻事实的证明。",
      "evidence_bridge" => "visible choice-and-relation motif → separate desire from commitment → test actual choices and consequences",
      "source_pages" => [185, 190]
    },
    "chariot" => {
      "transferable_method" => "从车辆、冠冕和前行姿态的 motif 出发，检验主体是在被运送、主动驾驶，还是把自我控制夸大成全能。",
      "author_specific_amplification" => "Nichols 把战车写成‘把我们带回家’的载具，并以恋人之后的自我加冕提醒：方向感可能同时是自我膨胀。",
      "deck_specific_material" => "作者会比较不同牌组的战车、权力与旅程图像；不把其他牌组的缰绳、乘客或车辆细节加入 RWS packet。",
      "polarity" => "自我推动、方向与承载／自我膨胀、孤立驾驶和超越限制的幻觉。",
      "alternative" => "若现实中路线由环境决定，战车 amplification 可只表示正在被一套过程带着走，而非个人完全掌控。",
      "projection_warning" => "不要从战车直接推断胜利、旅行、驾车或确定的行动结果。",
      "evidence_bridge" => "visible vehicle-and-directed-motion motif → distinguish agency from transport → test control against constraints",
      "source_pages" => [198, 205]
    },
    "justice" => {
      "transferable_method" => "从秤、直立姿态与两侧对照的 motif 出发，检查问题需要什么平衡、程序和可承担的责任。",
      "author_specific_amplification" => "Nichols 将正义置于‘平衡领域’，作为连接天与地的人类中介；平衡是主动综合，不是简单判定谁对谁错。",
      "deck_specific_material" => "作者的炼金术、阴阳和中排结构是方法材料，不替代现实法律程序或法律意见。",
      "polarity" => "公平、综合与责任／冷酷裁决、把自我偏见误当成客观。",
      "alternative" => "若外部程序并不公平，正义 amplification 可能首先要求校正信息与程序，而不是接受现成判决。",
      "projection_warning" => "不要把正义牌当作法院结论、法律胜负或道德定罪。",
      "evidence_bridge" => "visible balance-and-decision motif → identify competing claims and process → test accountable evidence",
      "source_pages" => [215, 220]
    },
    "hermit" => {
      "transferable_method" => "从孤独旅人、灯与缓慢步伐的 motif 出发，检查答案是否需要安静观察而不是外部认可。",
      "author_specific_amplification" => "Nichols 把隐者写成 Old Wise Man：他的智慧不是书本上的讲义，而是在沉默与孤独中以自身存在照亮路径。",
      "deck_specific_material" => "作者将隐者与老子、精神原型及旅人图像相连；这些不是现实人物年龄、身份或隐居事实。",
      "polarity" => "内在辨识、节制与独立／退缩、孤立和把沉默当成优越。",
      "alternative" => "若问题要求协作，隐者可以表示先形成自己的判断再回来沟通，而非永久退出。",
      "projection_warning" => "不要把斗篷、灯或独处直接推断成老人、导师或抑郁状态。",
      "evidence_bridge" => "visible solitary-lamp motif → create reflective distance → test whether withdrawal improves discernment",
      "source_pages" => [230, 240]
    },
    "wheel_of_fortune" => {
      "transferable_method" => "从轮转、上升与下降的 motif 出发，检验当下改变是循环、环境转折，还是可调整的态度。",
      "author_specific_amplification" => "Nichols 将命运之轮放在个人洞察之后，把焦点转向命运与自由意志的张力，以及人在周期中的姿态变化。",
      "deck_specific_material" => "作者比较轮上的动物、埃及神祇与 Jung 类型材料；这不证明现实中的命定事件或动物身份。",
      "polarity" => "周期、回归与机会／无力感、宿命论和把变化全部归给外力。",
      "alternative" => "若现实变化有明确人为原因，轮的 amplification 可退为识别周期与选择下一步姿态。",
      "projection_warning" => "不要把轮牌当作好运、厄运或精确时间点的保证。",
      "evidence_bridge" => "visible turning-and-cycle motif → separate circumstance from response → test what can still be chosen",
      "source_pages" => [248, 260]
    },
    "strength" => {
      "transferable_method" => "从人和狮子的近距离关系 motif 出发，检查力量是在压制、驯服，还是在有意识地整合本能。",
      "author_specific_amplification" => "Nichols 把力量写成‘谁的力量’：外在皇帝的命令与狮子的内在本能必须由中介关系整合，力量既可滋养也可吞噬。",
      "deck_specific_material" => "作者比较狮子、女性人物、道德与救赎等原型材料；这些不是当事人性别、动物或超能力的事实。",
      "polarity" => "温柔而有意识的整合／压抑、骄傲、欲望或被本能吞没。",
      "alternative" => "若现实只显示外部强制，较弱的读法是需要边界与安全，而不是已经完成内在整合。",
      "projection_warning" => "不要把力量牌直接读成勇敢、性格坚强、女性身份或对他人有控制力。",
      "evidence_bridge" => "visible human-lion relation motif → distinguish coercion from integration → test how power is enacted",
      "source_pages" => [276, 285]
    },
    "hanged_man" => {
      "transferable_method" => "从倒悬、单脚悬挂与暂停的 motif 出发，检验停滞是否提供了真实的视角转换，还是只是被动困住。",
      "author_specific_amplification" => "Nichols 将吊人写成悬置与 consent 的阶段：前一张牌的能量被反转，新的理解来自暂时不能按原方式行动。",
      "deck_specific_material" => "作者的树、深渊与蔬菜根部比较是作者图像材料，不是 RWS 视觉 packet 的替代。",
      "polarity" => "暂停、换位与让新理解形成／无助、牺牲叙事和把拖延合理化。",
      "alternative" => "若现实已有可行动的出口，吊人可提示先改变观察角度，而不要求无限等待。",
      "projection_warning" => "不要把倒挂直接推断成受害者身份、失败或必然牺牲。",
      "evidence_bridge" => "visible suspension-and-reversal motif → test whether perspective changes → separate deliberate pause from helpless delay",
      "source_pages" => [295, 300]
    },
    "death" => {
      "transferable_method" => "从骷髅、镰刀与散落身体部位的 motif 出发，检查旧结构哪些部分真的结束、哪些仍可被带入新安排。",
      "author_specific_amplification" => "Nichols 把死神接在吊人的精神死亡之后：被拆散的旧生活与旧人格不必整体消失，仍有活的部分会被纳入新的秩序。",
      "deck_specific_material" => "作者的收获、骨骼和仪式性死亡比较是象征扩展，不是现实死亡事件的预言。",
      "polarity" => "结束、重组与更新／执着旧秩序、把变化等同于毁灭。",
      "alternative" => "若现实只是阶段调整，死神可表示停止旧做法而非关系、工作或生命的字面终结。",
      "projection_warning" => "不要用死神断言死亡、疾病、失业或确定的灾难。",
      "evidence_bridge" => "visible dismemberment-and-transition motif → identify what is obsolete → test what remains viable",
      "source_pages" => [309, 320]
    },
    "temperance" => {
      "transferable_method" => "从天使、两只容器和液体流动的 motif 出发，检查相反资源如何被调和、循环和重新配比。",
      "author_specific_amplification" => "Nichols 将节制写成 Heavenly Alchemist：蓝、红容器之间的倾倒连接水瓶与流通，重点是混合与调节而非静态折中。",
      "deck_specific_material" => "作者的炼金术、水瓶和颜色联想属于作者材料；颜色不能回写 Phase 4C 视觉事实。",
      "polarity" => "调和、循环与转化／过度混合、稀释差异和以平静掩盖冲突。",
      "alternative" => "若现实双方并不具备可交换资源，节制可能只要求先建立节奏与边界。",
      "projection_warning" => "不要从天使或水流断言灵性身份、治疗效果或必然和解。",
      "evidence_bridge" => "visible pouring-and-balance motif → identify what can circulate → test proportion and boundaries",
      "source_pages" => [337, 345]
    },
    "devil" => {
      "transferable_method" => "从有翼人物、锁链和受约束的人形 motif 出发，检查欲望、权力或习惯是否在无意识中取得控制。",
      "author_specific_amplification" => "Nichols 将恶魔写成堕落的 Dark Angel：驱力本身未必有道德色彩，真正危险在于它以无意识、强迫和不受检验的方式运行。",
      "deck_specific_material" => "作者比较撒旦、影子、罪与其他宗教图像；这些不是犯罪、邪恶身份或超自然事实。",
      "polarity" => "承认驱力并有意识使用／无意识强迫、骄傲与被欲望吞没。",
      "alternative" => "若现实已有清楚边界，恶魔 amplification 可提示一项强吸引力的议题，而不是关系或行为已失控。",
      "projection_warning" => "不要把恶魔牌当作出轨、犯罪、成瘾或邪恶人格的证据。",
      "evidence_bridge" => "visible chain-and-attachment motif → separate drive from unconscious compulsion → test observable control",
      "source_pages" => [352, 365]
    },
    "tower" => {
      "transferable_method" => "从高塔、闪电和两人被抛出的 motif 出发，检查外在结构的破裂是否也打开了被保护结构之外的现实。",
      "author_specific_amplification" => "Nichols 把高塔写成 Destruction 与 Stroke of Liberation 的双面经验：被冠冕保护的结构被闪电击开，但释放不等于结果自动变好。",
      "deck_specific_material" => "作者以巴别塔、闪电和后续星月日的进程作扩展；不能把其他牌组人物动作加入 RWS packet。",
      "polarity" => "突然暴露、解放与真实更新／失序、受伤和失去原有防护。",
      "alternative" => "若现实已有主动拆除计划，高塔可表示加速清除旧结构，而非完全突发的灾难。",
      "projection_warning" => "不要把高塔直接预言死亡、事故、失业或确定的崩溃。",
      "evidence_bridge" => "visible lightning-and-ejection motif → test collapse versus liberation → preserve immediate instability as counterevidence",
      "source_pages" => [381, 390]
    },
    "star" => {
      "transferable_method" => "从裸露人物、双容器与星光的 motif 出发，检查去除旧身份后还有什么可以重新分配和滋养生活。",
      "author_specific_amplification" => "Nichols 将星星写成高塔之后的希望：人物失去墙和伪装却仍保有彼此，水被分别流回溪流与土地，形成更新而非简单乐观。",
      "deck_specific_material" => "作者的裸露、星体与炼金术联想是作者材料，不是用户现实的纯洁、裸体或希望证明。",
      "polarity" => "更新、诚实与可流动的资源／理想化、暴露过度和把希望当成结果。",
      "alternative" => "若现实仍处于失序，星星只可支持恢复方向，不证明已经恢复。",
      "projection_warning" => "不要把星星当作愿望实现、疗愈完成或关系必然修复。",
      "evidence_bridge" => "visible water-and-starlight renewal motif → identify what can be replenished → test hope against present resources",
      "source_pages" => [397, 410]
    },
    "moon" => {
      "transferable_method" => "从月光、两塔、犬与水中生物的 motif 出发，检查信息是否处于模糊、恐惧和未整合的边界。",
      "author_specific_amplification" => "Nichols 将月亮写成 Maiden or Menace：旅人不在画面中，龙虾阻路、犬守门，意味着人必须面对没有清晰引导的黑暗阶段。",
      "deck_specific_material" => "作者比较荒漠、龙虾、犬与古典月亮意象；这些不证明现实存在危险动物或欺骗者。",
      "polarity" => "直觉、过渡与潜意识材料／恐惧、幻觉和把未知误认成事实。",
      "alternative" => "若已有可核验资料，月亮可只提示情绪噪音与不完整信息，而不支持阴谋或欺骗。",
      "projection_warning" => "不要把月亮牌当作出轨、谎言、精神疾病或隐藏事件的证明。",
      "evidence_bridge" => "visible night-and-threshold motif → separate felt threat from verified fact → test uncertainty explicitly",
      "source_pages" => [420, 430]
    },
    "sun" => {
      "transferable_method" => "从太阳、人脸和两个孩子的 motif 出发，检查清晰、玩耍与关系是否让现实更可见，同时保留光线过强的风险。",
      "author_specific_amplification" => "Nichols 将太阳写成 Moon 之后的 Shining Center：龙虾与犬消失，两个孩子把人的关系带回日光，但照明仍可能诱发投射。",
      "deck_specific_material" => "作者比较太阳的人脸、彩色光线与炼金术的统一意象；这不替代 RWS packet 的颜色或人物事实。",
      "polarity" => "清晰、共同玩耍与生命能量／过度曝光、理想化和把光明当成无条件安全。",
      "alternative" => "若问题材料仍混乱，太阳可只是提供可检验的明确信息，而非保证快乐结局。",
      "projection_warning" => "不要把太阳直接当作成功、孩子、怀孕或未来必然顺利的证明。",
      "evidence_bridge" => "visible human-faced-light motif → identify what becomes clear → test warmth against concrete behavior",
      "source_pages" => [437, 445]
    },
    "judgement" => {
      "transferable_method" => "从天使号角、坟墓与起身人物的 motif 出发，检查一个呼唤是否需要被听见、评估并落实为新的参与。",
      "author_specific_amplification" => "Nichols 将审判写成 A Vocation：号角不是命定职业，而是一个让旧经验重新醒来、要求回应的召唤。",
      "deck_specific_material" => "作者的复活、圣经与天使材料只提供原型扩展，不证明死亡后事件或神谕。",
      "polarity" => "觉醒、回应与重新参与／羞耻、审判他人和把召唤误当成确定命运。",
      "alternative" => "若现实没有新机会，审判可表示对旧事实作出清楚总结，而不是立刻开始新人生。",
      "projection_warning" => "不要用审判预言复活、死亡、天命或必须接受的职业选择。",
      "evidence_bridge" => "visible trumpet-and-rising motif → distinguish call from verdict → test whether a concrete response is possible",
      "source_pages" => [450, 455]
    },
    "world" => {
      "transferable_method" => "从花环、舞者与四角守望者的 motif 出发，检查分散的经验是否被整合，同时保留循环尚未真正结束的可能。",
      "author_specific_amplification" => "Nichols 把世界写成 A Window on Eternity：舞者在花环中完成整合，却仍是通向下一轮旅程的窗口，不是把所有变化冻结成终点。",
      "deck_specific_material" => "作者明确比较角落的狮、牛、鹰和人形/天使以及舞者的两根权杖；其他传统的对应关系不可当作 RWS 新视觉事实。",
      "polarity" => "整合、完成与开放视野／停滞、封闭和把完成误当成永不改变。",
      "alternative" => "若现实仍有未协调部分，世界只支持看见整体结构，不证明项目或关系已经结束。",
      "projection_warning" => "不要把世界当作最终结局、永恒稳定或必然成功的保证。",
      "evidence_bridge" => "visible wreath-and-integration motif → map what has come together → test whether the next cycle remains open",
      "source_pages" => [464, 475, 488]
    }
  }.freeze

  def self.card_anchors(path)
    File.readlines(path).map { |line| JSON.parse(line) }.to_h { |row| [row.fetch("card_id"), row] }
  end

  def self.excerpt_ids(prefix, pages)
    pages.flat_map { |page| [format("%s.p%04d.e01", prefix, page)] }
  end

  DANIEL_MAJOR_CONTINUATIONS = {
    "magician" => 122, "high_priestess" => 124, "empress" => 126, "emperor" => 128,
    "hierophant" => 130, "lovers" => 132, "chariot" => 134, "strength" => 138,
    "hermit" => 140, "wheel_of_fortune" => 142, "justice" => 144, "hanged_man" => 146,
    "death" => 148, "temperance" => 150, "devil" => 154, "tower" => 156,
    "star" => 158, "moon" => 160, "sun" => 162, "judgement" => 164,
    "fool" => 166, "world" => 168
  }.freeze

  def self.daniel_author_interpretation(card_id)
    case card_id
    when "pentacles_page"
      ["Daniel 把錢幣侍者比作正在學做生意的學徒；這是作者對角色功能的解釋，不是 RWS 圖像中可見的職業身份。"]
    when "strength"
      ["Daniel 把女子控制獅子口部的親昵動作解釋為勇氣、智慧與以柔克剛；這是作者解釋，不是新增 visual fact。"]
    else
      []
    end
  end

  def self.daniel_units
    anchors = card_anchors(File.join(ROOT, "references/snapshot/anchors/daniel-card-entry-anchors.jsonl"))
    DANIEL.map do |card_id, (visual, meanings, process, examples)|
      anchor = anchors.fetch(card_id)
      opening_pages = anchor.fetch("pdf_pages")
      continuation = DANIEL_MAJOR_CONTINUATIONS[card_id]
      source_pages = (opening_pages + (continuation ? [continuation] : [])).uniq
      {
        "unit_id" => "daniel.#{card_id}.upright_baseline",
        "teacher" => "daniel",
        "canonical_card_id" => card_id,
        "capability" => "daniel_card_narrative",
        "orientation_scope" => "upright_baseline",
        "author_visual_narrative" => visual,
        "meaning_candidates" => meanings,
        "process_or_tension" => process,
        "example_manifestations" => examples,
        "author_interpretation" => daniel_author_interpretation(card_id),
        "limitations" => ["Daniel 的作者叙事不能覆盖 RWS visual facts；逆位机制不由本单元提供。", "候选必须由牌位、用户事实和邻牌筛选，不能当作固定牌义。"],
        "source_pages" => source_pages,
        "source_excerpt_ids" => excerpt_ids("daniel_16_lessons_zh", source_pages),
        "review_status" => "manually_reviewed_rendered_page",
        "source_quality" => "manual_page_reviewed_author_condensation",
        "visual_review_note" => continuation ?
          "Rendered Daniel opening page #{opening_pages.first} and continuation page #{continuation}; card image, labelled visual/meaning/example sections and the continuation meaning/example page were inspected. OCR text was used only as a locator and was not promoted." :
          "Rendered Daniel source PDF page #{opening_pages.first}; card image and labelled visual/meaning/example sections inspected. OCR text was used only as a locator and was not promoted."
      }
    end
  end

  def self.dawn_units
    pages = {
      "cups_king" => (71..76), "cups_queen" => (77..82), "cups_knight" => (83..89), "cups_page" => (90..94),
      "wands_king" => (95..101), "wands_queen" => (102..107), "wands_knight" => (108..112), "wands_page" => (113..118),
      "pentacles_king" => (119..124), "pentacles_queen" => (125..129), "pentacles_knight" => (130..135), "pentacles_page" => (136..140),
      "swords_king" => (141..145), "swords_queen" => (146..151), "swords_knight" => (152..157), "swords_page" => (158..162)
    }
    DAWN.map do |card_id, (name, rank, suit, archetype, strengths, shadows, behaviors, relationships, work, bridge)|
      suit_key = {"cups" => "聖杯", "wands" => "權杖", "swords" => "寶劍", "pentacles" => "錢幣"}.fetch(card_id.split("_").first)
      rank_function = RANKS.fetch(rank).first
      pgs = pages.fetch(card_id).to_a
      {
        "unit_id" => "dawn.#{card_id}.court",
        "teacher" => "dawn",
        "canonical_card_id" => card_id,
        "capability" => "dawn_court_ontology",
        "orientation_scope" => "court_context_baseline",
        "rank_function" => rank_function,
        "suit_expression" => "#{suit_key}：#{suit == "水" ? "情緒、直覺與關係" : suit == "火" ? "熱情、行動與可見影響" : suit == "土" ? "身體、工作與資源" : "語言、思考與界線"}",
        "archetype_name" => archetype,
        "strengths" => strengths,
        "shadow_or_failure_modes" => shadows,
        "observable_behaviors" => behaviors,
        "relationship_manifestations" => relationships,
        "work_or_social_manifestations" => work,
        "action_bridge" => bridge,
        "identity_limits" => ["原型是作者候選，不是现实身份、性别、年龄、星座或外貌证明。", "由牌位、邻牌、用户提供的可观察行为和现实约束决定是他人、self-aspect、角色还是行为模式。"],
        "limitations" => ["不以一张 Court 直接确认某个人；多 Court 不等于同样数量的人。", "不把流行文化角色、星座或职业列表当作事实。"],
        "source_pages" => pgs,
        "source_excerpt_ids" => pgs.map { |page| format("dawn_court_zh.ex%04d", page) },
        "review_status" => "manually_reviewed_rendered_pages",
        "source_quality" => "manual_page_reviewed_author_condensation",
        "visual_review_note" => "Rendered Dawn source PDF pages #{pgs.first}-#{pgs.last}; keyword, archetype, relationship, work, strength/shadow and action sections inspected."
      }
    end
  end

  def self.rank_units
    RANKS.map do |rank, (function, bridge)|
      pages = {"Page" => [46, 47, 48], "Knight" => [52, 54, 58, 59], "Queen" => [63, 64], "King" => [65, 66, 67, 68]}.fetch(rank)
      {
        "unit_id" => "dawn.rank.#{rank.downcase}", "teacher" => "dawn", "canonical_card_id" => nil,
        "capability" => "dawn_rank_function", "orientation_scope" => "court_context_baseline",
        "rank" => rank, "rank_function" => function, "functional_bridge" => bridge,
        "limitations" => ["rank 是功能轴，不是年龄、性别或道德等级；element、position、现实行为仍需共同筛选。"],
        "source_pages" => pages, "source_excerpt_ids" => pages.map { |page| format("dawn_court_zh.ex%04d", page) },
        "review_status" => "manually_reviewed_rendered_pages", "source_quality" => "manual_page_reviewed_author_condensation",
        "visual_review_note" => "Rendered Dawn rank-function pages and checked the rank labels against the source layout."
      }
    end
  end

  def self.greer_units
    source = card_anchors(File.join(ROOT, "references/snapshot/anchors/greer-card-entry-anchors.jsonl"))
    source.map do |card_id, row|
      canonical_id = if card_id.start_with?("the_")
                       card_id.delete_prefix("the_")
                     elsif card_id.match?(/_(一|二|三|四|五|六|七|八|九|十)$/)
                       suit, numeral = card_id.split("_")
                       number = {"一" => "ace", "二" => "two", "三" => "three", "四" => "four", "五" => "five", "六" => "six", "七" => "seven", "八" => "eight", "九" => "nine", "十" => "ten"}.fetch(numeral)
                       "#{suit}_#{number}"
                     elsif card_id.match?(/^(page|knight|queen|king)_of_(wands|cups|swords|pentacles)$/)
                       rank, suit = card_id.split("_of_")
                       "#{suit}_#{rank}"
                     else
                       card_id
                     end
      {
        "unit_id" => "greer.#{canonical_id}.reversal",
        "teacher" => "greer", "canonical_card_id" => canonical_id, "capability" => "greer_reversal_mechanism",
        "orientation_scope" => "reversed_only", "upright_baseline" => row.fetch("upright_baseline"),
        "reversal_mechanism_candidates" => row.fetch("reversal_mechanism_candidates"),
        "reversal_anchor" => row.fetch("reversal_anchor"), "context_switches" => row.fetch("context_switches"),
        "alternatives" => row.fetch("alternatives"), "counterevidence" => row.fetch("counterevidence"),
        "limitations" => ["仅在用户明确提供 reversed 时查询；orientation unspecified 不得调用。", "Greer 是候选机制来源，不覆盖 RWS visual facts 或用户事实。"],
        "source_pages" => row.fetch("source_pages"), "source_excerpt_ids" => row.fetch("source_excerpt_ids"),
        "review_status" => "normalized_from_substantive_reviewed_anchor", "source_quality" => "indexed_text_source_reviewed_by_phase_anchor",
        "visual_review_note" => "Normalized from the existing substantive Greer card-entry anchor; no new OCR text added."
      }
    end
  end

  def self.nichols_units
    chains = YAML.load_file(File.join(ROOT, "references/snapshot/anchors/nichols-reasoning-chains.yaml"))["chains"]
    chapters = chains.select { |chain| chain.fetch("chain_id").end_with?(".motif-to-human-experience") }
    cards = %w[fool magician high_priestess empress emperor hierophant lovers chariot justice hermit wheel_of_fortune strength hanged_man death temperance devil tower star moon sun judgement world]
    chapters.map.with_index do |chain, index|
      card_id = cards.fetch(index)
      detail = NICHOLS_DETAILS.fetch(card_id)
      pages = detail.fetch("source_pages")
      unit = {
        "unit_id" => "nichols.#{card_id}.major_amplification", "teacher" => "nichols", "canonical_card_id" => card_id,
        "capability" => "nichols_major_amplification", "orientation_scope" => "major_contextual",
        "transferable_method" => detail.fetch("transferable_method"),
        "author_specific_amplification" => detail.fetch("author_specific_amplification"),
        "deck_specific_material" => detail.fetch("deck_specific_material"),
        "polarity" => detail.fetch("polarity"),
        "alternative" => detail.fetch("alternative"),
        "projection_warning" => detail.fetch("projection_warning"),
        "evidence_bridge" => detail.fetch("evidence_bridge"),
        "limitations" => ["只在具体 Major motif、progression、projection 或 polarity 实际改变判断时调用；单独出现大牌不构成调用理由。", "不提供固定权重、编号分数或事件预测。"],
        "source_pages" => pages, "source_excerpt_ids" => pages.map { |page| format("nichols_jung_tarot_en.p%04d.e01", page) },
        "review_status" => "manually_reviewed_authored_chapter_model", "source_quality" => "authored_chapter_model_backed",
        "visual_review_note" => "Rendered Nichols chapter opening and selected detail pages #{pages.join(', ')}; chapter title, card-specific motif, amplification and limitation were checked. Comparative deck material remains explicitly non-RWS."
      }
      unit["source_page_support"] = detail.fetch("source_page_support") if detail.key?("source_page_support")
      unit
    end
  end

  def self.write_yaml(path, payload)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, YAML.dump(payload))
  end

  def self.source_chunk_index(book_id)
    path = SOURCE_CHUNKS.fetch(book_id)
    raise "missing source chunks for #{book_id}: #{path}" unless File.file?(path)
    File.foreach(path).map { |line| JSON.parse(line) }.to_h { |row| [row.fetch("excerpt_id"), row] }
  end

  def self.validate_explicit_source_routes!(daniel, nichols)
    daniel_source = source_chunk_index("daniel_16_lessons_zh")
    daniel.fetch("units").each do |unit|
      unit.fetch("source_pages").zip(unit.fetch("source_excerpt_ids")).each do |page, excerpt_id|
        row = daniel_source.fetch(excerpt_id) { raise "Daniel excerpt is not in source chunks: #{excerpt_id}" }
        raise "Daniel page drift for #{excerpt_id}" unless row.fetch("pdf_page") == page
      end
    end

    nichols_source = source_chunk_index("nichols_jung_tarot_en")
    nichols.fetch("units").each do |unit|
      card_id = unit.fetch("canonical_card_id")
      expected_chapter = NICHOLS_CHAPTERS.fetch(card_id)
      if unit.key?("source_page_support")
        support = unit.fetch("source_page_support")
        unless support.keys.map(&:to_s).sort == unit.fetch("source_pages").map(&:to_s).sort &&
               support.values.all? { |value| value.to_s.strip.length >= 20 }
          raise "Nichols page support is incomplete for #{card_id}"
        end
      end
      unit.fetch("source_pages").zip(unit.fetch("source_excerpt_ids")).each do |page, excerpt_id|
        row = nichols_source.fetch(excerpt_id) { raise "Nichols excerpt is not in source chunks: #{excerpt_id}" }
        unless row.fetch("pdf_page") == page && row.fetch("chapter_id") == expected_chapter
          raise "Nichols page/chapter drift for #{card_id}: #{excerpt_id}"
        end
      end
    end
  end

  def self.run!
    daniel = {"teacher" => "daniel", "book_id" => "daniel_16_lessons_zh", "status" => "manually_reviewed", "unit_count" => DANIEL.length, "units" => daniel_units}
    nichols = {"teacher" => "nichols", "book_id" => "nichols_jung_tarot_en", "status" => "authored_chapter_model_backed", "unit_count" => nichols_units.length, "units" => nichols_units}
    validate_explicit_source_routes!(daniel, nichols)
    write_yaml(File.join(OUT, "daniel-card-units.yaml"), daniel)
    write_yaml(File.join(OUT, "nichols-amplification-units.yaml"), nichols)
  end
end

TarotTeacherEvidenceBuilder.run! if $PROGRAM_NAME == __FILE__
