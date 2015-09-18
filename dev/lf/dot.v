Set Implicit Arguments.

Require Import LibLN.
Require Import Coq.Program.Equality.

(* ###################################################################### *)
(* ###################################################################### *)
(** * Definitions *)

(* ###################################################################### *)
(** ** Syntax *)

Parameter typ_label: Set.
Parameter trm_label: Set.

Inductive label: Set :=
| label_typ: typ_label -> label
| label_trm: trm_label -> label.

Inductive avar : Set :=
  | avar_b : nat -> avar  (* bound var (de Bruijn index) *)
  | avar_f : var -> avar. (* free var ("name"), refers to store or ctx *)

Inductive typ : Set :=
  | typ_rcd  : dec -> typ (* { D } *)
  | typ_and  : typ -> typ -> typ
  | typ_sel  : avar -> typ_label -> typ (* x.L *)
  | typ_bnd  : typ -> typ (* rec(x: T) *)
  | typ_all  : typ -> typ -> typ (* all(x: S)T *)
with dec : Set :=
  | dec_typ  : typ_label -> typ -> typ -> dec (* A: S..U *)
  | dec_trm  : trm_label -> typ -> dec (* a: T *).

Inductive trm : Set :=
  | trm_var  : avar -> trm
  | trm_val  : val -> trm
  | trm_sel  : avar -> trm_label -> trm
  | trm_app  : avar -> avar -> trm
  | trm_let  : trm -> trm -> trm (* let x = t in u *)
with val : Set :=
  | val_new  : typ -> defs -> val
  | val_lambda : typ -> trm -> val
with def : Set :=
  | def_typ  : typ_label -> typ -> def
  | def_trm  : trm_label -> trm -> def
with defs : Set :=
  | defs_nil : defs
  | defs_cons : defs -> def -> defs.

(** *** Typing environment ("Gamma") *)
Definition ctx := env typ.

(** *** Value environment ("store") *)
Definition sto := env val.

(* ###################################################################### *)
(** ** Definition list membership *)

Definition label_of_def(d: def): label := match d with
| def_typ L _ => label_typ L
| def_trm m _ => label_trm m
end.

Definition label_of_dec(D: dec): label := match D with
| dec_typ L _ _ => label_typ L
| dec_trm m _ => label_trm m
end.

Fixpoint get_def(l: label)(ds: defs): option def :=
match ds with
| defs_nil => None
| defs_cons ds' d => If label_of_def d = l then Some d else get_def l ds'
end.

Definition defs_has(ds: defs)(d: def) := get_def (label_of_def d) ds = Some d.
Definition defs_hasnt(ds: defs)(l: label) := get_def l ds = None.

(* ###################################################################### *)
(** ** Opening *)

(** Opening replaces in some syntax a bound variable with dangling index (k)
   by a free variable x. *)

Definition open_rec_avar (k: nat) (u: var) (a: avar) : avar :=
  match a with
  | avar_b i => If k = i then avar_f u else avar_b i
  | avar_f x => avar_f x
  end.

Fixpoint open_rec_typ (k: nat) (u: var) (T: typ): typ :=
  match T with
  | typ_rcd D      => typ_rcd (open_rec_dec k u D)
  | typ_and T1 T2  => typ_and (open_rec_typ k u T1) (open_rec_typ k u T2)
  | typ_sel x L    => typ_sel (open_rec_avar k u x) L
  | typ_bnd T      => typ_bnd (open_rec_typ (S k) u T)
  | typ_all T1 T2  => typ_all (open_rec_typ k u T1) (open_rec_typ (S k) u T2)
  end
with open_rec_dec (k: nat) (u: var) (D: dec): dec :=
  match D with
  | dec_typ L T U => dec_typ L (open_rec_typ k u T) (open_rec_typ k u U)
  | dec_trm m T => dec_trm m (open_rec_typ k u T)
  end.

Fixpoint open_rec_trm (k: nat) (u: var) (t: trm): trm :=
  match t with
  | trm_var a      => trm_var (open_rec_avar k u a)
  | trm_val v      => trm_val (open_rec_val k u v)
  | trm_sel v m    => trm_sel (open_rec_avar k u v) m
  | trm_app f a    => trm_app (open_rec_avar k u f) (open_rec_avar k u a)
  | trm_let t1 t2  => trm_let (open_rec_trm k u t1) (open_rec_trm (S k) u t2)
  end
with open_rec_val (k: nat) (u: var) (v: val): val :=
  match v with
  | val_new T ds => val_new (open_rec_typ (S k) u T) (open_rec_defs (S k) u ds)
  | val_lambda T e => val_lambda (open_rec_typ k u T) (open_rec_trm (S k) u e)
  end
with open_rec_def (k: nat) (u: var) (d: def): def :=
  match d with
  | def_typ L T => def_typ L (open_rec_typ k u T)
  | def_trm m e => def_trm m (open_rec_trm k u e)
  end
with open_rec_defs (k: nat) (u: var) (ds: defs): defs :=
  match ds with
  | defs_nil => defs_nil
  | defs_cons tl d => defs_cons (open_rec_defs k u tl) (open_rec_def k u d)
  end.

Definition open_avar u a := open_rec_avar  0 u a.
Definition open_typ  u t := open_rec_typ   0 u t.
Definition open_dec  u D := open_rec_dec   0 u D.
Definition open_trm  u e := open_rec_trm   0 u e.
Definition open_val  u v := open_rec_val   0 u v.
Definition open_def  u d := open_rec_def   0 u d.
Definition open_defs u l := open_rec_defs  0 u l.

(* ###################################################################### *)
(** ** Free variables *)

Definition fv_avar (a: avar) : vars :=
  match a with
  | avar_b i => \{}
  | avar_f x => \{x}
  end.

Fixpoint fv_typ (T: typ) : vars :=
  match T with
  | typ_rcd D      => (fv_dec D)
  | typ_and T U    => (fv_typ T) \u (fv_typ U)
  | typ_sel x L    => (fv_avar x)
  | typ_bnd T      => (fv_typ T)
  | typ_all T1 T2  => (fv_typ T1) \u (fv_typ T2)
  end
with fv_dec (D: dec) : vars :=
  match D with
  | dec_typ L T U => (fv_typ T) \u (fv_typ U)
  | dec_trm m T   => (fv_typ T)
  end.

Fixpoint fv_trm (t: trm) : vars :=
  match t with
  | trm_var a       => (fv_avar a)
  | trm_val v        => (fv_val v)
  | trm_sel x m      => (fv_avar x)
  | trm_app f a      => (fv_avar f) \u (fv_avar a)
  | trm_let t1 t2    => (fv_trm t1) \u (fv_trm t2)
  end
with fv_val (v: val) : vars :=
  match v with
  | val_new T ds    => (fv_typ T) \u (fv_defs ds)
  | val_lambda T e  => (fv_typ T) \u (fv_trm e)
  end
with fv_def (d: def) : vars :=
  match d with
  | def_typ _ T     => (fv_typ T)
  | def_trm _ t     => (fv_trm t)
  end
with fv_defs(ds: defs) : vars :=
  match ds with
  | defs_nil         => \{}
  | defs_cons tl d   => (fv_defs tl) \u (fv_def d)
  end.

Definition fv_ctx_types(G: ctx): vars := (fv_in_values (fun T => fv_typ T) G).

(* ###################################################################### *)
(** ** Operational Semantics *)

Inductive red : trm -> sto -> trm -> sto -> Prop :=
| red_sel : forall x m s t T ds,
    binds x (val_new T ds) s ->
    defs_has ds (def_trm m t) ->
    red (trm_sel (avar_f x) m) s t s
| red_app : forall f a s T t,
    binds f (val_lambda T t) s ->
    red (trm_app (avar_f f) (avar_f a)) s (open_trm a t) s
| red_let : forall v t s x,
    x # s ->
    red (trm_let (trm_val v) t) s (open_trm x t) (s & x ~ v)
| red_let_var : forall t s x,
    red (trm_let (trm_var (avar_f x)) t) s (open_trm x t) s
| red_let_tgt : forall t0 t s t0' s',
    red t0 s t0' s' ->
    red (trm_let t0 t) s (trm_let t0' t) s'.

(* ###################################################################### *)
(** ** Typing *)

Inductive tymode: Set := ty_precise | ty_general.
Inductive submode: Set := sub_tight | sub_general.

Inductive ty_trm : tymode -> submode -> ctx -> trm -> typ -> Prop :=
| ty_var : forall m1 m2 G x T,
    binds x T G ->
    ty_trm m1 m2 G (trm_var (avar_f x)) T
| ty_all_intro : forall L m1 m2 G T t U,
    wf_typ G T ->
    (forall x, x \notin L ->
      ty_trm m1 sub_general (G & x ~ T) t (open_typ x U)) ->
    ty_trm m1 m2 G (trm_val (val_lambda T t)) (typ_all T U)
| ty_all_elim : forall m2 G x z S T,
    ty_trm ty_general m2 G (trm_var (avar_f x)) (typ_all S T) ->
    ty_trm ty_general m2 G (trm_var (avar_f z)) S ->
    ty_trm ty_general m2 G (trm_app (avar_f x) (avar_f z)) (open_typ z T)
| ty_new_intro : forall L m1 m2 G T ds,
    (forall x, x \notin L ->
      wf_typ (G & (x ~ open_typ x T)) (open_typ x T)) ->
    (forall x, x \notin L ->
      ty_defs (G & (x ~ open_typ x T)) (open_defs x ds) (open_typ x T)) ->
    ty_trm m1 m2 G (trm_val (val_new T ds)) (typ_bnd T)
| ty_new_elim : forall m2 G x m T,
    ty_trm ty_general m2 G (trm_var (avar_f x)) (typ_rcd (dec_trm m T)) ->
    ty_trm ty_general m2 G (trm_sel (avar_f x) m) T
| ty_rec_elim : forall m1 m2 G x T,
    ty_trm m1 m2 G (trm_var (avar_f x)) (typ_bnd T) ->
    ty_trm m1 m2 G (trm_var (avar_f x)) (open_typ x T)
| ty_let : forall L m2 G t u T U,
    ty_trm ty_general m2 G t T ->
    (forall x, x \notin L ->
      ty_trm ty_general sub_general (G & x ~ T) u U) ->
    wf_typ G U ->
    ty_trm ty_general m2 G (trm_let t u) U
| ty_sub : forall m1 m2 G t T U,
    (m1 = ty_precise -> exists x, t = trm_var (avar_f x)) ->
    ty_trm m1 m2 G t T ->
    subtyp m1 m2 G T U ->
    ty_trm m1 m2 G t U
with ty_def : ctx -> def -> dec -> Prop :=
| ty_def_typ : forall G A T,
    wf_typ G T ->
    ty_def G (def_typ A T) (dec_typ A T T)
| ty_def_trm : forall G a t T,
    ty_trm ty_general sub_general G t T ->
    ty_def G (def_trm a t) (dec_trm a T)
with ty_defs : ctx -> defs -> typ -> Prop :=
| ty_defs_one : forall G d D,
    ty_def G d D ->
    ty_defs G (defs_cons defs_nil d) (typ_rcd D)
| ty_defs_cons : forall G ds d T D,
    ty_defs G ds T ->
    ty_def G d D ->
    defs_hasnt ds (label_of_def d) ->
    ty_defs G (defs_cons ds d) (typ_and T (typ_rcd D))

with subtyp : tymode -> submode -> ctx -> typ -> typ -> Prop :=
| subtyp_refl: forall m2 G T,
    subtyp ty_general m2 G T T
| subtyp_trans: forall m1 m2 G S T U,
    subtyp m1 m2 G S T ->
    subtyp m1 m2 G T U ->
    subtyp m1 m2 G S U
| subtyp_and11: forall m1 m2 G T U,
    subtyp m1 m2 G (typ_and T U) T
| subtyp_and12: forall m1 m2 G T U,
    subtyp m1 m2 G (typ_and T U) U
| subtyp_and2: forall m2 G S T U,
    subtyp ty_general m2 G S T ->
    subtyp ty_general m2 G S U ->
    subtyp ty_general m2 G S (typ_and T U)
| subtyp_fld: forall m2 G a T U,
    subtyp ty_general m2 G T U ->
    subtyp ty_general m2 G (typ_rcd (dec_trm a T)) (typ_rcd (dec_trm a U))
| subtyp_typ: forall m2 G A S1 T1 S2 T2,
    subtyp ty_general m2 G S2 S1 ->
    subtyp ty_general m2 G T1 T2 ->
    subtyp ty_general m2 G (typ_rcd (dec_typ A S1 T1)) (typ_rcd (dec_typ A S2 T2))
| subtyp_sel2: forall G x A S T,
    ty_trm ty_general sub_general G (trm_var (avar_f x)) (typ_rcd (dec_typ A S T)) ->
    subtyp ty_general sub_general G S (typ_sel (avar_f x) A)
| subtyp_sel1: forall G x A S T,
    ty_trm ty_general sub_general G (trm_var (avar_f x)) (typ_rcd (dec_typ A S T)) ->
    subtyp ty_general sub_general G (typ_sel (avar_f x) A) T
| subtyp_sel2_tight: forall G x A T,
    ty_trm ty_general sub_tight G (trm_var (avar_f x)) (typ_rcd (dec_typ A T T)) ->
    subtyp ty_general sub_tight G T (typ_sel (avar_f x) A)
| subtyp_sel1_tight: forall G x A T,
    ty_trm ty_general sub_tight G (trm_var (avar_f x)) (typ_rcd (dec_typ A T T)) ->
    subtyp ty_general sub_tight G (typ_sel (avar_f x) A) T
| subtyp_bnd: forall L m2 G T U,
    (forall x, x \notin L ->
       subtyp ty_general sub_general (G & x ~ (open_typ x T)) (open_typ x T) (open_typ x U)) ->
    subtyp ty_general m2 G (typ_bnd T) (typ_bnd U)
| subtyp_all: forall L m2 G S1 T1 S2 T2,
    subtyp ty_general m2 G S2 S1 ->
    wf_typ G S2 ->
    (forall x, x \notin L ->
       subtyp ty_general sub_general (G & x ~ S2) T1 T2) ->
    subtyp ty_general m2 G (typ_all S1 T1) (typ_all S2 T2)

with wf_typ : ctx -> typ -> Prop :=
| wft_fld: forall G a T,
     wf_typ G T ->
     wf_typ G (typ_rcd (dec_trm a T))
| wft_typ: forall G A T U,
     wf_typ G T ->
     wf_typ G U ->
     wf_typ G (typ_rcd (dec_typ A T U))
| wft_and: forall G T U,
     wf_typ G T ->
     wf_typ G U ->
     wf_typ G (typ_and T U)
| wft_sel: forall G x A T U,
     ty_trm ty_general sub_general G (trm_var (avar_f x)) (typ_rcd (dec_typ A T U)) ->
     wf_typ G (typ_sel (avar_f x) A)
| wft_bnd: forall L G T,
     (forall x, x \notin L ->
        wf_typ (G & x ~ open_typ x T) (open_typ x T)) ->
     wf_typ G (typ_bnd T)
| wft_all: forall L G T U,
     wf_typ G T ->
     (forall x, x \notin L ->
        wf_typ (G & x ~ T) U) ->
     wf_typ G (typ_all T U).

Inductive wf_sto: ctx -> sto -> Prop :=
| wf_sto_empty: wf_sto empty empty
| wf_sto_push: forall G s x T v,
    wf_sto G s ->
    x # G ->
    x # s ->
    ty_trm ty_precise sub_general G (trm_val v) T ->
    wf_sto (G & x ~ T) (s & x ~ v).

(* ###################################################################### *)
(* ###################################################################### *)
(** * Infrastructure *)

(* ###################################################################### *)
(** ** Induction principles *)

Scheme typ_mut := Induction for typ Sort Prop
with   dec_mut := Induction for dec Sort Prop.
Combined Scheme typ_mutind from typ_mut, dec_mut.

Scheme trm_mut  := Induction for trm  Sort Prop
with   def_mut  := Induction for def  Sort Prop
with   defs_mut := Induction for defs Sort Prop.
Combined Scheme trm_mutind from trm_mut, def_mut, defs_mut.

Scheme ty_trm_mut    := Induction for ty_trm    Sort Prop
with   ty_def_mut    := Induction for ty_def    Sort Prop
with   ty_defs_mut   := Induction for ty_defs   Sort Prop.
Combined Scheme ty_mutind from ty_trm_mut, ty_def_mut, ty_defs_mut.

Scheme rules_trm_mut    := Induction for ty_trm    Sort Prop
with   rules_def_mut    := Induction for ty_def    Sort Prop
with   rules_defs_mut   := Induction for ty_defs   Sort Prop
with   rules_subtyp     := Induction for subtyp    Sort Prop
with   rules_wf_typ     := Induction for wf_typ    Sort Prop.
Combined Scheme rules_mutind from rules_trm_mut, rules_def_mut, rules_defs_mut, rules_subtyp, rules_wf_typ.

(* ###################################################################### *)
(** ** Tactics *)

Ltac gather_vars :=
  let A := gather_vars_with (fun x : vars      => x         ) in
  let B := gather_vars_with (fun x : var       => \{ x }    ) in
  let C := gather_vars_with (fun x : ctx       => (dom x) \u (fv_ctx_types x)) in
  let D := gather_vars_with (fun x : sto       => dom x     ) in
  let E := gather_vars_with (fun x : avar      => fv_avar  x) in
  let F := gather_vars_with (fun x : trm       => fv_trm   x) in
  let G := gather_vars_with (fun x : val       => fv_val   x) in
  let H := gather_vars_with (fun x : def       => fv_def   x) in
  let I := gather_vars_with (fun x : defs      => fv_defs  x) in
  let J := gather_vars_with (fun x : typ       => fv_typ   x) in
  constr:(A \u B \u C \u D \u E \u F \u G \u H \u I \u J).

Ltac pick_fresh x :=
  let L := gather_vars in (pick_fresh_gen L x).

Ltac in_empty_contradiction :=
  solve [match goal with
  | H: _ \in \{} |- _ => rewrite in_empty in H; exfalso; exact H
  end].

Ltac eq_specialize :=
  repeat match goal with
  | H:                 _ = _ -> _ |- _ => specialize (H         eq_refl)
  | H: forall _      , _ = _ -> _ |- _ => specialize (H _       eq_refl)
  | H: forall _ _    , _ = _ -> _ |- _ => specialize (H _ _     eq_refl)
  | H: forall _ _ _  , _ = _ -> _ |- _ => specialize (H _ _ _   eq_refl)
  | H: forall _ _ _ _, _ = _ -> _ |- _ => specialize (H _ _ _ _ eq_refl)
  end.

Ltac crush := eq_specialize; eauto.

Tactic Notation "apply_fresh" constr(T) "as" ident(x) :=
  apply_fresh_base T gather_vars x.

Hint Constructors
  ty_trm ty_def ty_defs
  subtyp
  wf_typ.

Hint Constructors wf_sto.

Lemma fresh_push_eq_inv: forall A x a (E: env A),
  x # (E & x ~ a) -> False.
Proof.
  intros. rewrite dom_push in H. false H. rewrite in_union.
  left. rewrite in_singleton. reflexivity.
Qed.

(* ###################################################################### *)
(* ###################################################################### *)
(** * Proofs *)

(* ###################################################################### *)
(** ** Weakening *)

Lemma weaken_rules:
  (forall m1 m2 G t T, ty_trm m1 m2 G t T -> forall G1 G2 G3,
    G = G1 & G3 ->
    ok (G1 & G2 & G3) ->
    ty_trm m1 m2 (G1 & G2 & G3) t T) /\
  (forall G d D, ty_def G d D -> forall G1 G2 G3,
    G = G1 & G3 ->
    ok (G1 & G2 & G3) ->
    ty_def (G1 & G2 & G3) d D) /\
  (forall G ds T, ty_defs G ds T -> forall G1 G2 G3,
    G = G1 & G3 ->
    ok (G1 & G2 & G3) ->
    ty_defs (G1 & G2 & G3) ds T) /\
  (forall m1 m2 G T U, subtyp m1 m2 G T U -> forall G1 G2 G3,
    G = G1 & G3 ->
    ok (G1 & G2 & G3) ->
    subtyp m1 m2 (G1 & G2 & G3) T U) /\
  (forall G T, wf_typ G T -> forall G1 G2 G3,
    G = G1 & G3 ->
    ok (G1 & G2 & G3) ->
    wf_typ (G1 & G2 & G3) T).
Proof.
  apply rules_mutind; try solve [eauto].
  + intros. subst.
    eapply ty_var. eapply binds_weaken; eauto.
  + intros. subst.
    apply_fresh ty_all_intro as z. eauto.
    assert (zL: z \notin L) by auto.
    specialize (H0 z zL G1 G2 (G3 & z ~ T)).
    repeat rewrite concat_assoc in H0.
    apply* H0.
  + intros. subst.
    apply_fresh ty_new_intro as z; assert (zL: z \notin L) by auto.
    - specialize (H z zL G1 G2 (G3 & z ~ open_typ z T)).
      repeat rewrite concat_assoc in H.
      apply* H.
    - specialize (H0 z zL G1 G2 (G3 & z ~ open_typ z T)).
      repeat rewrite concat_assoc in H0.
      apply* H0.
  + intros. subst.
    apply_fresh ty_let as z. eauto.
    assert (zL: z \notin L) by auto.
    specialize (H0 z zL G1 G2 (G3 & z ~ T)).
    repeat rewrite concat_assoc in H0.
    apply* H0.
    eauto.
  + intros. subst.
    apply_fresh subtyp_bnd as z.
    assert (zL: z \notin L) by auto.
    specialize (H z zL G1 G2 (G3 & z ~ open_typ z T)).
    repeat rewrite concat_assoc in H.
    apply* H.
  + intros. subst.
    apply_fresh subtyp_all as z.
    eauto.
    eauto.
    assert (zL: z \notin L) by auto.
    specialize (H1 z zL G1 G2 (G3 & z ~ S2)).
    repeat rewrite concat_assoc in H1.
    apply* H1.
  + intros. subst.
    apply_fresh wft_bnd as z.
    assert (zL: z \notin L) by auto.
    specialize (H z zL G1 G2 (G3 & z ~ open_typ z T)).
    repeat rewrite concat_assoc in H.
    apply* H.
  + intros. subst.
    apply_fresh wft_all as z. eauto.
    assert (zL: z \notin L) by auto.
    specialize (H0 z zL G1 G2 (G3 & z ~ T)).
    repeat rewrite concat_assoc in H0.
    apply* H0.
Qed.

Lemma weaken_ty_trm:  forall m1 m2 G1 G2 t T,
    ty_trm m1 m2 G1 t T ->
    ok (G1 & G2) ->
    ty_trm m1 m2 (G1 & G2) t T.
Proof.
  intros.
    assert (G1 & G2 = G1 & G2 & empty) as EqG. {
    rewrite concat_empty_r. reflexivity.
  }
  rewrite EqG. apply* weaken_rules.
  rewrite concat_empty_r. reflexivity.
  rewrite <- EqG. assumption.
Qed.

(* ###################################################################### *)
(** ** Well-formed store *)

Lemma wf_sto_to_ok_s: forall s G,
  wf_sto G s -> ok s.
Proof. intros. induction H; jauto. Qed.

Lemma wf_sto_to_ok_G: forall s G,
  wf_sto G s -> ok G.
Proof. intros. induction H; jauto. Qed.

Hint Resolve wf_sto_to_ok_s wf_sto_to_ok_G.

Lemma ctx_binds_to_sto_binds_raw: forall s G x T,
  wf_sto G s ->
  binds x T G ->
  exists G1 G2 v, G = G1 & (x ~ T) & G2 /\ binds x v s /\ ty_trm ty_precise sub_general G1 (trm_val v) T.
Proof.
  introv Wf Bi. gen x T Bi. induction Wf; intros.
  + false* binds_empty_inv.
  + unfolds binds. rewrite get_push in *. case_if.
    - inversions Bi. exists G (@empty typ) v.
      rewrite concat_empty_r. auto.
    - specialize (IHWf _ _ Bi). destruct IHWf as [G1 [G2 [ds' [Eq [Bi' Tyds]]]]].
      subst. exists G1 (G2 & x ~ T) ds'. rewrite concat_assoc. auto.
Qed.

Lemma sto_binds_to_ctx_binds_raw: forall s G x v,
  wf_sto G s ->
  binds x v s ->
  exists G1 G2 T, G = G1 & (x ~ T) & G2 /\ ty_trm ty_precise sub_general G1 (trm_val v) T.
Proof.
  introv Wf Bi. gen x v Bi. induction Wf; intros.
  + false* binds_empty_inv.
  + unfolds binds. rewrite get_push in *. case_if.
    - inversions Bi. exists G (@empty typ) T.
      rewrite concat_empty_r. auto.
    - specialize (IHWf _ _ Bi). destruct IHWf as [G1 [G2 [T0' [Eq Ty]]]].
      subst. exists G1 (G2 & x ~ T) T0'. rewrite concat_assoc. auto.
Qed.

Lemma invert_wf_sto_concat: forall s G1 G2,
  wf_sto (G1 & G2) s ->
  exists s1 s2, s = s1 & s2 /\ wf_sto G1 s1.
Proof.
  introv Wf. gen_eq G: (G1 & G2). gen G1 G2. induction Wf; introv Eq; subst.
  - do 2 exists (@empty val). rewrite concat_empty_r.
    apply empty_concat_inv in Eq. destruct Eq. subst. auto.
  - destruct (env_case G2) as [Eq1 | [x' [T' [G2' Eq1]]]].
    * subst G2. rewrite concat_empty_r in Eq. subst G1.
      exists (s & x ~ v) (@empty val). rewrite concat_empty_r. auto.
    * subst G2. rewrite concat_assoc in Eq. apply eq_push_inv in Eq.
      destruct Eq as [? [? ?]]. subst x' T' G. specialize (IHWf G1 G2' eq_refl).
      destruct IHWf as [s1 [s2 [Eq Wf']]]. subst.
      exists s1 (s2 & x ~ v). rewrite concat_assoc. auto.
Qed.

Lemma sto_unbound_to_ctx_unbound: forall s G x,
  wf_sto G s ->
  x # s ->
  x # G.
Proof.
  introv Wf Ub_s.
  induction Wf.
  + auto.
  + destruct (classicT (x0 = x)) as [Eq | Ne].
    - subst. false (fresh_push_eq_inv Ub_s).
    - auto.
Qed.

Lemma ctx_unbound_to_sto_unbound: forall s G x,
  wf_sto G s ->
  x # G ->
  x # s.
Proof.
  introv Wf Ub.
  induction Wf.
  + auto.
  + destruct (classicT (x0 = x)) as [Eq | Ne].
    - subst. false (fresh_push_eq_inv Ub).
    - auto.
Qed.

Lemma typing_implies_bound: forall m1 m2 G x T,
  ty_trm m1 m2 G (trm_var (avar_f x)) T ->
  exists S, binds x S G.
Proof.
  intros. remember (trm_var (avar_f x)) as t. induction H; try solve [inversion Heqt].
  - inversion Heqt. subst. exists T. assumption.
  - inversion Heqt. subst. eapply IHty_trm. reflexivity.
  - subst. eapply IHty_trm. reflexivity.
Qed.

Lemma typing_bvar_implies_false: forall m1 m2 G a T,
  ty_trm m1 m2 G (trm_var (avar_b a)) T ->
  False.
Proof.
  intros. remember (trm_var (avar_b a)) as t. induction H; try solve [inversion Heqt].
  eapply IHty_trm. auto.
Qed.

(* ###################################################################### *)
(** ** Some Lemmas *)

Lemma corresponding_types: forall G s x T,
  wf_sto G s ->
  binds x T G ->
  ((exists S U t, binds x (val_lambda S t) s /\
                  ty_trm ty_precise sub_general G (trm_val (val_lambda S t)) (typ_all S U) /\
                  T = typ_all S U) \/
   (exists S ds, binds x (val_new S ds) s /\
                 ty_trm ty_precise sub_general G (trm_val (val_new S ds)) (typ_bnd S) /\
                 T = typ_bnd S)).
Proof.
  introv H Bi. induction H.
  - false* binds_empty_inv.
  - unfolds binds. rewrite get_push in *. case_if.
    + inversions Bi. inversion H2; subst.
      * left. exists T0. exists U. exists t.
        split. auto. split.
        apply weaken_ty_trm. assumption. apply ok_push. eapply wf_sto_to_ok_G. eassumption. assumption.
        reflexivity.
      * right. exists T0. exists ds.
        split. auto. split.
        apply weaken_ty_trm. assumption. apply ok_push. eapply wf_sto_to_ok_G. eassumption. assumption.
        reflexivity.
      * assert (exists x, trm_val v = trm_var (avar_f x)) as A. {
          apply H3. reflexivity.
        }
        destruct A as [? A]. inversion A.
    + specialize (IHwf_sto Bi).
      inversion IHwf_sto as [IH | IH].
      * destruct IH as [S [U [t [IH1 [IH2 IH3]]]]].
        left. exists S. exists U. exists t.
        split. assumption. split.
        apply weaken_ty_trm. assumption. apply ok_push. eapply wf_sto_to_ok_G. eassumption. assumption.
        assumption.
      * destruct IH as [S [ds [IH1 [IH2 IH3]]]].
        right. exists S. exists ds.
        split. assumption. split.
        apply weaken_ty_trm. assumption. apply ok_push. eapply wf_sto_to_ok_G. eassumption. assumption.
        assumption.
Qed.

Lemma unique_rec_subtyping: forall G S T,
  subtyp ty_precise sub_general G (typ_bnd S) T ->
  T = typ_bnd S.
Proof.
  introv Hsub.
  remember (typ_bnd S) as T'.
  remember ty_precise as m1.
  remember sub_general as m2.
  induction Hsub; try solve [inversion Heqm1].
  - specialize (IHHsub1 HeqT' Heqm1 Heqm2). subst.
    apply IHHsub2; reflexivity.
  - inversion HeqT'.
  - inversion HeqT'.
Qed.

Lemma unique_all_subtyping: forall G S U T,
  subtyp ty_precise sub_general G (typ_all S U) T ->
  T = typ_all S U.
Proof.
  introv Hsub.
  remember (typ_all S U) as T'.
  remember ty_precise as m1.
  remember sub_general as m2.
  induction Hsub; try solve [inversion Heqm1].
  - specialize (IHHsub1 HeqT' Heqm1 Heqm2). subst.
    apply IHHsub2; reflexivity.
  - inversion HeqT'.
  - inversion HeqT'.
Qed.

Lemma unique_lambda_typing: forall G x S U T,
  binds x (typ_all S U) G ->
  ty_trm ty_precise sub_general G (trm_var (avar_f x)) T ->
  T = typ_all S U.
Proof.
  introv Bi Hty.
  remember (trm_var (avar_f x)) as t.
  remember ty_precise as m1.
  remember sub_general as m2.
  induction Hty; try solve [inversion Heqt].
  - inversions Heqt.
    unfold binds in Bi. unfold binds in H.
    rewrite H in Bi. inversion Bi.
    reflexivity.
  - specialize (IHHty Bi Heqt Heqm1 Heqm2).
    inversion IHHty.
  - specialize (IHHty Bi Heqt Heqm1 Heqm2).
    rewrite IHHty in H0. rewrite Heqm1 in H0. rewrite Heqm2 in H0.
    apply unique_all_subtyping in H0.
    apply H0.
Qed.

Lemma lambda_not_rcd: forall G x S U A T,
  binds x (typ_all S U) G ->
  ty_trm ty_precise sub_general G (trm_var (avar_f x)) (typ_rcd (dec_typ A T T)) ->
  False.
Proof.
  introv Bi Hty.
  assert (typ_rcd (dec_typ A T T) = typ_all S U) as Contra. {
    eapply unique_lambda_typing; eassumption.
  }
  inversion Contra.
Qed.

Inductive record_typ : typ -> fset label -> Prop :=
| rt_one : forall D l,
  l = label_of_dec D ->
  record_typ (typ_rcd D) \{l}
| rt_cons: forall T ls D l,
  record_typ T ls ->
  l = label_of_dec D ->
  l \notin ls ->
  record_typ (typ_and T (typ_rcd D)) (union ls \{l})
.

Definition record_type T := exists ls, record_typ T ls.

Lemma open_dec_preserves_label: forall D x i,
  label_of_dec D = label_of_dec (open_rec_dec i x D).
Proof.
  intros. induction D; simpl; reflexivity.
Qed.

Lemma open_record_typ: forall T x ls,
  record_typ T ls -> record_typ (open_typ x T) ls.
Proof.
  intros. induction H.
  - unfold open_typ. simpl.
    apply rt_one.
    rewrite <- open_dec_preserves_label. assumption.
  - unfold open_typ. simpl.
    apply rt_cons; try assumption.
    rewrite <- open_dec_preserves_label. assumption.
Qed.

Lemma open_record_typ_rev: forall T x ls,
  record_typ (open_typ x T) ls -> record_typ T ls.
Proof.
  intros. remember (open_typ x T) as TX.
  generalize dependent T.
  induction H; intros.
  - destruct T; unfold open_typ in HeqTX; simpl in HeqTX; inversion HeqTX.
    subst.
    rewrite <- open_dec_preserves_label.
    apply rt_one; eauto.
  - destruct T0; unfold open_typ in HeqTX; simpl in HeqTX; inversion HeqTX.
    subst.
    destruct T0_2; unfold open_typ in H4; simpl in H4; inversion H4.
    subst.
    rewrite <- open_dec_preserves_label.
    apply rt_cons; try assumption.
    eapply IHrecord_typ. eauto. eauto.
    rewrite <- open_dec_preserves_label in H1. apply H1.
Qed.

Lemma open_record_type: forall T x,
  record_type T -> record_type (open_typ x T).
Proof.
  intros. destruct H as [ls H]. exists ls. eapply open_record_typ.
  eassumption.
Qed.

Lemma open_record_type_rev: forall T x,
  record_type (open_typ x T) -> record_type T.
Proof.
  intros. destruct H as [ls H]. exists ls. eapply open_record_typ_rev.
  eassumption.
Qed.

Lemma label_same_typing: forall G d D,
  ty_def G d D -> label_of_def d = label_of_dec D.
Proof.
  intros. inversion H; subst; simpl; reflexivity.
Qed.

Lemma record_defs_typing_rec: forall G ds S,
  ty_defs G ds S ->
  exists ls, record_typ S ls /\ forall l, l \notin ls <-> defs_hasnt ds l.
Proof.
  intros. induction H.
  - eexists. split.
    apply rt_one. reflexivity.
    apply label_same_typing in H. rewrite <- H.
    intros. split; intro A.
    + unfold defs_hasnt. simpl.
      apply notin_singleton in A.
      rewrite If_r. reflexivity. eauto.
    + unfold defs_hasnt in A. unfold get_def in A.
      case_if. apply notin_singleton. eauto.
  - destruct IHty_defs as [ls [IH1 IH2]].
    eexists. split.
    apply rt_cons; try eassumption. reflexivity.
    apply label_same_typing in H0. rewrite <- H0.
    specialize (IH2 (label_of_def d)).
    destruct IH2 as [IH2A IH2B].
    apply IH2B. assumption.
    intros. split; intro A.
    + specialize (IH2 l).
      destruct IH2 as [IH2A IH2B].
      unfold defs_hasnt. simpl.
      rewrite If_r. unfold defs_hasnt in IH2A. apply IH2A.
      apply notin_union in A. destruct A as [A1 A2]. assumption.
      apply notin_union in A. destruct A as [A1 A2]. apply notin_singleton in A2.
      apply label_same_typing in H0. rewrite <- H0 in A2. eauto.
    + apply notin_union. split.
      * specialize (IH2 l).
        destruct IH2 as [IH2A IH2B].
        apply IH2B. inversion A.
        case_if. unfold defs_hasnt. assumption.
      * apply label_same_typing in H0. rewrite <- H0.
        unfold defs_hasnt in A. unfold get_def in A.
        case_if in A.
        apply notin_singleton. eauto.
Qed.

Lemma record_defs_typing: forall G ds S,
  ty_defs G ds S ->
  record_type S.
Proof.
  intros.
  assert (exists ls, record_typ S ls /\ forall l, l \notin ls <-> defs_hasnt ds l) as A.
  eapply record_defs_typing_rec; eauto.
  destruct A as [ls [A1 A2]].
  exists ls. apply A1.
Qed.

Lemma record_new_typing: forall G S ds,
  ty_trm ty_precise sub_general G (trm_val (val_new S ds)) (typ_bnd S) ->
  record_type S.
Proof.
  intros.
  inversion H; subst.
  + pick_fresh x.
   apply open_record_type_rev with (x:=x).
   eapply record_defs_typing. eapply H6. eauto.
  + assert (exists x, trm_val (val_new S ds) = trm_var (avar_f x)) as Contra. {
      apply H0; eauto.
    }
    destruct Contra as [? Contra]. inversion Contra.
Qed.

Inductive record_sub : typ -> typ -> Prop :=
| rs_refl: forall T,
  record_sub T T
| rs_dropl: forall T T' D,
  record_sub T T' ->
  record_sub (typ_and T (typ_rcd D)) (typ_rcd D)
| rs_drop: forall T T' D,
  record_sub T T' ->
  record_sub (typ_and T (typ_rcd D)) T'
| rs_pick: forall T T' D,
  record_sub T T' ->
  record_sub (typ_and T (typ_rcd D)) (typ_and T' (typ_rcd D))
.

Lemma record_typ_sub_closed : forall T T' ls,
  record_sub T T' ->
  record_typ T ls ->
  exists ls', record_typ T' ls' /\ subset ls' ls.
Proof.
  introv Hsub Htyp. generalize dependent ls.
  induction Hsub; intros.
  - exists ls. split. assumption. apply subset_refl.
  - inversion Htyp; subst.
    eexists. split.
    eapply rt_one. reflexivity.
    rewrite <- union_empty_l with (E:=\{ label_of_dec D}) at 1.
    apply subset_union_2. apply subset_empty_l. apply subset_refl.
  - inversion Htyp; subst.
    specialize (IHHsub ls0 H1). destruct IHHsub as [ls' [IH1 IH2]].
    exists ls'. split. assumption.
    rewrite <- union_empty_r with (E:=ls').
    apply subset_union_2. assumption. apply subset_empty_l.
  - inversion Htyp; subst.
    specialize (IHHsub ls0 H1). destruct IHHsub as [ls0' [IH1 IH2]].
    exists (ls0' \u \{ label_of_dec D }). split.
    apply rt_cons; eauto.
    unfold "\c" in IH2. unfold "\notin". intro I.
    specialize (IH2 (label_of_dec D) I). eauto.
    apply subset_union_2. assumption. apply subset_refl.
Qed.

Lemma record_type_sub_closed : forall T T',
  record_sub T T' ->
  record_type T ->
  record_type T'.
Proof.
  introv Hsub Htype. destruct Htype as [ls Htyp].
  apply record_typ_sub_closed with (ls:=ls) in Hsub; try assumption.
  destruct Hsub as [ls' [Htyp' ?]].
  exists ls'. apply Htyp'.
Qed.

Lemma record_sub_trans: forall T1 T2 T3,
  record_sub T1 T2 ->
  record_sub T2 T3 ->
  record_sub T1 T3.
Proof.
  introv H12 H23. generalize dependent T3.
  induction H12; intros.
  - assumption.
  - inversion H23; subst. eapply rs_dropl. eassumption.
  - apply rs_drop. apply IHrecord_sub. assumption.
  - inversion H23; subst.
    + apply rs_pick. assumption.
    + eapply rs_dropl. eassumption.
    + apply rs_drop. apply IHrecord_sub. assumption.
    + apply rs_pick. apply IHrecord_sub. assumption.
Qed.

Lemma record_subtyping: forall G T T',
  subtyp ty_precise sub_general G T T' ->
  record_type T ->
  record_sub T T'.
Proof.
  introv Hsub Hr. generalize dependent Hr. dependent induction Hsub.
  - intros HS.
    apply record_sub_trans with (T2:=T).
    apply IHHsub1. apply HS.
    apply IHHsub2.
    eapply record_type_sub_closed. apply IHHsub1. apply HS. apply HS.
  - intros Htype. destruct Htype as [ls Htyp].
    inversion Htyp; subst.
    apply rs_drop. apply rs_refl.
  - intros Htype. destruct Htype as [ls Htyp].
    inversion Htyp; subst.
    eapply rs_dropl. apply rs_refl.
Qed.

Lemma record_typ_sub_label_in: forall T D ls,
  record_typ T ls ->
  record_sub T (typ_rcd D) ->
  label_of_dec D \in ls.
Proof.
  introv Htyp Hsub. generalize dependent D. induction Htyp; intros.
  - inversion Hsub. subst. apply in_singleton_self.
  - inversion Hsub; subst.
    + rewrite in_union. right. apply in_singleton_self.
    + rewrite in_union. left. apply IHHtyp. assumption.
Qed.

Lemma unique_rcd_typ: forall T A T1 T2,
  record_type T ->
  record_sub T (typ_rcd (dec_typ A T1 T1)) ->
  record_sub T (typ_rcd (dec_typ A T2 T2)) ->
  T1 = T2.
Proof.
  introv Htype Hsub1 Hsub2.
  generalize dependent T2. generalize dependent T1. generalize dependent A.
  destruct Htype as [ls Htyp]. induction Htyp; intros; inversion Hsub1; inversion Hsub2; subst.
  - inversion H4. subst. reflexivity.
  - inversion H8. subst. reflexivity.
  - apply record_typ_sub_label_in with (D:=dec_typ A T2 T2) in Htyp.
    simpl in Htyp. simpl in H0. unfold "\notin" in H0. unfold not in H0.
    specialize (H0 Htyp). inversion H0.
    assumption.
  - apply record_typ_sub_label_in with (D:=dec_typ A T1 T1) in Htyp.
    simpl in Htyp. simpl in H0. unfold "\notin" in H0. unfold not in H0.
    specialize (H0 Htyp). inversion H0.
    assumption.
  - eapply IHHtyp; eassumption.
Qed.

Lemma record_type_sub_not_rec: forall S T x,
  record_sub (open_typ x S) (typ_bnd T) ->
  record_type S ->
  False.
Proof.
  introv Hsub Htype. remember (open_typ x S) as Sx.
  apply open_record_type with (x:=x) in Htype.
  rewrite <- HeqSx in Htype. clear HeqSx.
  destruct Htype as [ls Htyp]. induction Htyp.
  - inversion Hsub.
  - inversion Hsub; subst. apply IHHtyp. assumption.
Qed.

Lemma shape_new_typing: forall G x S T,
  binds x (typ_bnd S) G ->
  record_type S ->
  ty_trm ty_precise sub_general G (trm_var (avar_f x)) T ->
  T = typ_bnd S \/ record_sub (open_typ x S) T.
Proof.
  introv Bi HS Hx. dependent induction Hx.
  - unfold binds in H. unfold binds in Bi. rewrite H in Bi. inversion Bi.
    left. reflexivity.
  - assert (typ_bnd T = typ_bnd S \/ record_sub (open_typ x S) (typ_bnd T)) as A. {
      eapply IHHx; eauto.
    }
    destruct A as [A | A].
    + inversion A. right. apply rs_refl.
    + apply record_type_sub_not_rec in A. inversion A. assumption.
  - assert (T = typ_bnd S \/ record_sub (open_typ x S) T) as A. {
      eapply IHHx; eauto.
    }
    destruct A as [A | A].
    + subst. apply unique_rec_subtyping in H0. left. assumption.
    + right. eapply record_sub_trans. eassumption.
      eapply record_subtyping. eassumption.
      eapply record_type_sub_closed. eassumption.
      eapply open_record_type. assumption.
Qed.

Lemma unique_tight_bounds: forall G s x T1 T2 A,
  wf_sto G s ->
  ty_trm ty_precise sub_general G (trm_var (avar_f x)) (typ_rcd (dec_typ A T1 T1)) ->
  ty_trm ty_precise sub_general G (trm_var (avar_f x)) (typ_rcd (dec_typ A T2 T2)) ->
  T1 = T2.
Proof.
  introv Hwf Hty1 Hty2.
  assert (exists T, binds x T G) as Bi. {
    eapply typing_implies_bound. eassumption.
  }
  destruct Bi as [T Bi].
  destruct (corresponding_types Hwf Bi).
  - destruct H as [S [U [t [Bis [Ht EqT]]]]].
    false.
    eapply lambda_not_rcd.
    subst. eassumption. eassumption.
  - destruct H as [S [ds [Bis [Ht EqT]]]]. subst.
    assert (record_type S) as Htype. {
      eapply record_new_typing. eassumption.
    }
    destruct (shape_new_typing Bi Htype Hty1) as [Contra1 | A1].
    inversion Contra1.
    destruct (shape_new_typing Bi Htype Hty2) as [Contra2 | A2].
    inversion Contra2.
    assert (record_type (open_typ x S)) as HXtype. {
      apply open_record_type. assumption.
    }
    eapply unique_rcd_typ.
    apply HXtype.
    eassumption.
    eassumption.
Qed.

(* If G ~ s, s |- x = new(x: T)d, and G |-# x: {A: S..U} then G |-# x.A <: U and G |-# S <: x.A. *)
Lemma tight_bound_completeness: forall G s x T ds A S U,
  wf_sto G s ->
  binds x (val_new T ds) s ->
  ty_trm ty_general sub_tight G (trm_var (avar_f x)) (typ_rcd (dec_typ A S U)) ->
  subtyp ty_general sub_tight G (typ_sel (avar_f x) A) U /\
  subtyp ty_general sub_tight G S (typ_sel (avar_f x) A).
Proof.
  introv Hwf Bis Hty.
  assert (exists T, binds x T G) as Bi. {
    eapply typing_implies_bound. eassumption.
  }
  destruct Bi as [Tx Bi].
  apply corresponding_types with (x:=x) (T:=Tx) in Hwf; try assumption.
  destruct Hwf as [Hex | Hex].
  destruct Hex as [? [? [? [Bis' ?]]]].
  unfold binds in Bis'. unfold binds in Bis. rewrite Bis' in Bis. inversion Bis.
  destruct Hex as [? [? [Bis' [Htyx EqTx]]]].
  unfold binds in Bis'. unfold binds in Bis. rewrite Bis' in Bis. inversions Bis.
  admit.  
Qed.

(* ###################################################################### *)
(** ** Possible types *)

(*
Definition (Possible types)

For a variable x, non-variable value v, environment G, the set Ts(G, x, v) of possible types of x defined as v in G is the smallest set SS such that:

If v = new(x: T)d then T in SS.
If v = new(x: T)d and {a = t} in d and G |- t: T' then {a: T'} in SS.
If v = new(x: T)d and {A = T'} in d and G |- S <: T', G |- T' <: U then {A: S..U} in SS.
If v = lambda(x: T)t and G |- T' <: T and G, x: T' |- t: U then all(x: T')U in SS.
If S1 in SS and S2 in SS then S1 & S2 in SS.
If S in SS and G |-! y: {A: S..S} then y.A in SS.
If S in SS then rec(x: S) in SS.
*)

Inductive possible_types: ctx -> var -> val -> typ -> Prop :=
| pt_new : forall G x T ds,
  possible_types G x (val_new T ds) (open_typ x T)
| pt_rcd_trm : forall G x T ds a t T',
  defs_has (open_defs x ds) (def_trm a t) ->
  ty_trm ty_general sub_general G t T' ->
  possible_types G x (val_new T ds) (typ_rcd (dec_trm a T'))
| pt_rcd_typ : forall G x T ds A T' S U,
  defs_has (open_defs x ds) (def_typ A T') ->
  subtyp ty_general sub_general G S T' ->
  subtyp ty_general sub_general G T' U ->
  possible_types G x (val_new T ds) (typ_rcd (dec_typ A S U))
| pt_lambda : forall L G x T t T' U,
  subtyp ty_general sub_general G T' T ->
  (forall y, y \notin L ->
    ty_trm ty_general sub_general (G & y ~ T') (open_trm y t) (open_typ y U)) ->
  possible_types G x (val_lambda T t) (typ_all T' U)
| pt_and : forall G x v S1 S2,
  possible_types G x v S1 ->
  possible_types G x v S2 ->
  possible_types G x v (typ_and S1 S2)
| pt_sel : forall G x v y A S,
  possible_types G x v S ->
  ty_trm ty_general sub_general G (trm_var y) (typ_rcd (dec_typ A S S)) ->
  possible_types G x v (typ_sel y A)
| pt_bnd : forall G x v S S',
  possible_types G x v S ->
  S = open_typ x S' ->
  possible_types G x v (typ_bnd S')
.

(*
Lemma (Possible types closure)

If G ~ s and G |- x: T and s |- x = v then Ts(G, x, v) is closed wrt G |- _ <: _.

Let SS = Ts(G, x, v). We first show SS is closed wrt G |-# _ <: _.

Assume T0 in SS and G |- T0 <: U0.s We show U0 in SS by an induction on subtyping derivations of G |-# T0 <: U0.
*)

Lemma possible_types_closure: forall G s x v S T,
  wf_sto G s ->
  binds x v s ->
  possible_types G x v S ->
  subtyp ty_general sub_general G S T ->
  possible_types G x v T.
Proof.
  admit.
Qed.

(*
Lemma (Possible types)

If G ~ s and G |- x: T then, for some non-variable value v, s |- x = v and T in Ts(G, x, v).
 *)

Lemma possible_types_lemma: forall G s x T,
  wf_sto G s ->
  ty_trm ty_general sub_general G (trm_var (avar_f x)) T ->
  exists v, binds x v s /\ possible_types G x v T.
Proof.
  admit.
Qed.

(*
Lemma (Canonical forms 1)

If G ~ s and G |- v: all(x: T)U for some non-variable value v, then v is of the form lambda(x: T')t where G |- T <: T' and G, x: T' |- t: U.
Proof: By (Possible Types), v cannot be a new because all(x: T)U is not a possible type of a new. So v must be of the form lambda(x: T')t. Again by (Possible Types) the only way a lambda(x: T')t can have a type all(x: T)U is if G |- T' <: T, G, x: T' |- t: U.
 *)

(*
Lemma (Canonical forms 2)

If G ~ s and G |- v: {a: T} for some non-variable value v, then v is of the form new(x: S)d for some x, S, d such that x = new(x: S)d in s, G |- d: S and d contains a definition {a = t} where G |- t: T.

Proof: By (Possible Types) v cannot be a lambda because {a: T} is not a possible type of a lambda. So v must be of the form new(x: S)d. Again by (Possible Types) the only way a new(x: S)d can have a type {a: T} is if there is a definition {a = t} in d and G |- t: T.
*)
