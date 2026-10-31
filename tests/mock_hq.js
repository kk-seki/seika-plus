(role)=>{
 const now=Date.now(),iso=m=>new Date(now-m*60000).toISOString(),today=ymdKey(new Date()),yday=ymdKey(new Date(now-864e5));
 const T={
  hq_settings_v1500:[{key:'stage2_stock',value:false}],
  hq_lots_v1400:[
   {id:'L1',lot_no:'H261025-01',qr_key:'K1',item_name:'キャベツ',status:'在庫あり',current_qty:8,unit:'case',pack_weight:'10kg',grade:'good',hq_received_date:today,source_kind:'石岡から',planned_qty:8,received_qty:8,supplier:'みどり農園（架空）',origin:'茨城県'},
   {id:'L2',lot_no:'H261025-02',qr_key:'K2',item_name:'玉ねぎ',status:'在庫あり',current_qty:6,unit:'case',pack_weight:'20kg',grade:'review',hq_received_date:today,source_kind:'直接入荷',planned_qty:6,received_qty:6,supplier:'さくら青果（架空）',photo_paths:['x'],issues:['傷み'],purchase_staff:'青木 一郎'},
   {id:'L3',lot_no:'H261024-05',qr_key:'K3',item_name:'人参',status:'入荷待ち',current_qty:0,unit:'case',pack_weight:'10kg',source_kind:'石岡から',planned_qty:5,received_qty:null}],
  hq_works_v1500:[
   {id:'W1',kind:'下処理',status:'作業中',confirm_status:'未確定',work_date:today,raw_item_name:'キャベツ',product_name:'キャベツ千切り',place:'作業台A',started_at:iso(45)},
   {id:'W2',kind:'下処理',status:'入力待ち',confirm_status:'未確定',work_date:today,raw_item_name:'玉ねぎ',product_name:'玉ねぎスライス',place:'作業台B',started_at:iso(120),ended_at:iso(5)},
   {id:'W3',kind:'下処理',status:'清掃中',confirm_status:'未確定',work_date:today,raw_item_name:'キャベツ',product_name:'キャベツざく切り',place:'作業台C',started_at:iso(150),ended_at:iso(20),yield_kg:72,waste_kg:6,inputs_saved_at:iso(15),inputs_saved_by_name:'下処理',label_printed_at:iso(12),label_print_count:1,expiry_date:ymdKey(new Date(now+2*864e5)),label_count:4},
   {id:'W4',kind:'作業',status:'作業中',task_name:'袋詰め',place:'作業台D',work_date:today,started_at:iso(30)},
   {id:'W5',kind:'下処理',status:'完了',confirm_status:'未確定',work_date:yday,raw_item_name:'人参',product_name:'人参千切り',place:'作業台A',started_at:iso(1500),ended_at:iso(1400),yield_kg:40,waste_kg:4,inputs_saved_at:iso(1400),inputs_saved_by_name:'下処理'}],
  hq_work_materials_v1500:[{id:'M1',work_id:'W1',lot_id:'L1',lot_no:'H261025-01',item_name:'キャベツ',unit:'case',pack_kg:10},{id:'M2',work_id:'W2',lot_id:'L2',lot_no:'H261025-02',item_name:'玉ねぎ',unit:'case',pack_kg:20},{id:'M3',work_id:'W3',lot_id:'L1',lot_no:'H261025-01',item_name:'キャベツ',unit:'case',pack_kg:10,qty:8},{id:'M5',work_id:'W5',lot_id:'L3',lot_no:'H261024-05',item_name:'人参',unit:'case',pack_kg:10,qty:5}],
  hq_work_members_v1500:[
   {id:'P1',work_id:'W1',staff_id:'S1',staff_name:'佐藤 花子',team:'1班',phase:'作業',start_at:iso(45)},{id:'P2',work_id:'W1',staff_id:'S2',staff_name:'鈴木 美咲',team:'1班',phase:'作業',start_at:iso(45)},
   {id:'P3',work_id:'W2',staff_id:'S3',staff_name:'高橋 由美',team:'2班',phase:'作業',start_at:iso(120),end_at:iso(5)},
   {id:'P4',work_id:'W3',staff_id:'S4',staff_name:'田中 恵',team:'2班',phase:'作業',start_at:iso(150),end_at:iso(20)},{id:'P5',work_id:'W3',staff_id:'S4',staff_name:'田中 恵',team:'2班',phase:'清掃',start_at:iso(20)},
   {id:'P6',work_id:'W4',staff_id:'S5',staff_name:'伊藤 京子',team:'3班',phase:'作業',start_at:iso(30)},{id:'P7',work_id:'W5',staff_id:'S1',staff_name:'佐藤 花子',team:'1班',phase:'作業',start_at:iso(1500),end_at:iso(1400)}],
  hq_staff_v1500:[['S1','佐藤 花子','1班','A'],['S2','鈴木 美咲','1班','A'],['S3','高橋 由美','2班','B'],['S4','田中 恵','2班','B'],['S5','伊藤 京子','3班','C'],['S6','渡辺 里美','3班','C']].map(([id,name,team,g])=>({id,name,team,group_name:g,qr_code:'STAFF-'+id})),
  hq_teams_v1500:[{name:'1班',group_name:'A'},{name:'2班',group_name:'B'},{name:'3班',group_name:'C'}],
  hq_places_v1500:['作業台A','作業台B','作業台C','作業台D'].map((name,i)=>({id:'PL'+i,name,active:true,sort:i})),
  hq_tasks_v1500:['袋詰め','洗浄','計量'].map((name,i)=>({id:'T'+i,name,active:true,sort:i})),
  hq_prep_masters_v1500:[{id:'PM1',name:'キャベツ千切り',item_name:'キャベツ',default_pack_kg:5,expiry_days:2,active:true},{id:'PM2',name:'キャベツざく切り',item_name:'キャベツ',default_pack_kg:5,expiry_days:2,active:true},{id:'PM3',name:'玉ねぎスライス',item_name:'玉ねぎ',default_pack_kg:4,expiry_days:2,active:true}],
  hq_items_v1400:[{name:'キャベツ',active:true},{name:'玉ねぎ',active:true},{name:'人参',active:true}],
  hq_normal_items_v1410:[{name:'じゃがいも',pack_weight_kg:10,active:true},{name:'長ねぎ',pack_weight_kg:5,active:true}],
  hq_stock_counts_v1500:[{kind:'原料',item_name:'じゃがいも',count_date:yday,total_kg:40,total_cases:4,lines:[{pack_kg:10,cases:4}],user_name:'本社 一郎'}],
  hq_destinations_v1400:[{name:'下処理',active:true},{name:'原料出し',active:true}],hq_stocktakes_v1500:[],hq_quality_dismiss_v1500:[],hq_diff_acks_v1500:[],
  hq_waste_v1500:[{id:'X1',kind:'下処理ロス',item_name:'人参',kg:4,waste_date:yday,user_name:'本社 一郎'},{id:'X2',kind:'原料出しロス',item_name:'キャベツ',kg:2.5,waste_date:today,user_name:'荷受 太郎'}]
 };
 const filt=(rows,q)=>{for(const p of String(q).split('&')){let m;if(m=p.match(/^(\w+)=eq\.(.*)$/)){const v=decodeURIComponent(m[2]);rows=rows.filter(r=>String(r[m[1]])===v)}else if(m=p.match(/^(\w+)=in\.\((.*)\)$/)){const vs=decodeURIComponent(m[2]).split(',');rows=rows.filter(r=>vs.includes(String(r[m[1]])))}else if(m=p.match(/^(\w+)=neq\.(.*)$/)){rows=rows.filter(r=>String(r[m[1]])!==decodeURIComponent(m[2]))}else if(m=p.match(/^(\w+)=is\.null$/)){rows=rows.filter(r=>r[m[1]]==null)}}return rows};
 qrSelect=async(t,q)=>JSON.parse(JSON.stringify(filt(T[t]||[],q)));
 callRpc=async(n,a)=>{if(n==='get_hq_stock_table_v1500')return{rows:[],count_days:[]};return []};
 window.alert=()=>{};window.confirm=()=>true;
 db.role=role;db.user=role==='hq_prep'?'下処理':role==='hq_receiver'?'荷受 太郎':'本社 一郎';
 window.__T=T;
}
