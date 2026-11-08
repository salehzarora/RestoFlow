package com.restoflow.pos

import org.json.JSONObject
import java.io.File

/** Local cross-layer replay; input contains synthetic SQL/Edge public response data only. */
fun main(args: Array<String>) {
    val wire = JSONObject(File(args.single()).readText())
    val issued = wire.getJSONObject("issued")
    val install = "20000000-0000-4000-8000-000000000001"
    val endpoint = "https://synthetic.invalid/functions/v1/pos-order-alert-status"
    val staged = DutyJournal.stage(install,"synthetic-device/PIN",endpoint,5)
        .put("consent_id",issued.getString("consent_id"))
    val unarmed = JSONObject().put("installation_id",install).put(DutyJournal.STAGED,staged)
    check(DutyJournal.queue(DutyJournal.stopped(unarmed,false,false)).isEmpty())
    println("PASS declined or interrupted preview-only reservation permits ordinary alerts without an endless cancellation")
    staged.put("started_tick",100L).put("status_secret",DutyJournal.token())
    val interrupted = DutyJournal.stopped(JSONObject(unarmed.toString()),false,false)
    check(DutyJournal.queue(interrupted).single() == DutyJournal.proof(staged))
    val bind = mapOf("identity" to staged.getString("identity"),"endpoint" to endpoint,"installation_id" to install,
        "consent_id" to issued.getString("consent_id"),"shift_id" to issued.getString("shift_id"),
        "registration_id" to issued.getString("registration_id"),"registration_generation" to issued.getString("generation"),
        "policy_revision" to issued.getString("policy_revision"),"server_time" to issued.getString("server_time"),
        "authority_expires_at" to issued.getString("authority_expires_at"))
    check(DutyJournal.bind(staged,bind + ("policy_revision" to 10),200,unarmed) == null)
    check(DutyJournal.bind(staged,bind + ("consent_id" to install),200,unarmed) == null)
    val active = DutyJournal.bind(staged,bind,200,unarmed)!!
    val scope = DutyJournal.scope(active)!!
    check(scope.policy == issued.getString("policy_revision"))
    check(active.getLong("authority_deadline") == 100L + BackgroundOrderAlertProtocol.timestamp(bind.getValue("authority_expires_at"))!! -
        BackgroundOrderAlertProtocol.timestamp(bind.getValue("server_time"))!!)
    println("PASS actual issued UUID policy and absolute server duration bind; reject differently scoped consent or numeric policy")
    val status = wire.getJSONObject("status")
    check(BackgroundOrderAlertDuty.validReply(status.opt("ok"),status.opt("consent_id"),status.opt("registration_id"),status.opt("generation"),scope))
    val confirmed = DutyJournal.snapshot(status,scope,active,200,210)
    check(confirmed.deadline <= active.getLong("authority_deadline"))
    for (bad in listOf<Any>(JSONObject.NULL,"true","false",0,1,false)) {
        check(runCatching { DutyJournal.snapshot(JSONObject(status.toString()).put("ok",bad),scope,active,200,210) }.isFailure)
    }
    val wake = wire.getJSONObject("wake")
    val data = wake.keys().asSequence().associateWith { wake.getString(it) }
    val wall = BackgroundOrderAlertProtocol.timestamp(status.getString("server_time"))!!
    check(BackgroundOrderAlertHints().accept(data,scope.registration,wall,0,scope))
    check(!BackgroundOrderAlertHints().accept(data,scope.registration,wall,0,scope.copy(consent=install)))
    println("PASS actual status and v2 wake through Kotlin production parser; superseded consent suppressed")
    val off = DutyJournal.stopped(active,false,false)
    val restored = JSONObject(off.toString())
    val proof = DutyJournal.queue(restored).single()
    check(restored.keys().asSequence().toSet() == setOf("installation_id",DutyJournal.QUEUE))
    check(restored.getJSONArray(DutyJournal.QUEUE).getJSONObject(0).keys().asSequence().toSet() ==
        setOf("installation_id","consent_id","revoke_secret"))
    check(proof.consent == scope.consent && proof.secret != staged.getString("status_secret"))
    check(DutyJournal.scope(restored) == null && !restored.has("enabled") && !restored.has("status_secret"))
    val delayed = BackgroundOrderAlertDuty.acknowledge(DutyJournal.queue(restored),proof,"true",scope.consent)
    check(delayed.single() == proof)
    DutyJournal.setQueue(restored,BackgroundOrderAlertDuty.acknowledge(delayed,proof,true,scope.consent))
    check(!DutyJournal.owns(restored))
    val fresh = DutyJournal.stage(install,bind.getValue("identity"),endpoint,5)
    check(fresh.getString("consent_id") != proof.consent && DutyJournal.proof(fresh).secret != proof.secret)
    fresh.put("started_tick",120).put("status_secret",DutyJournal.token())
    val newActive = DutyJournal.bind(fresh,bind + ("consent_id" to fresh.getString("consent_id")),201,off)!!
    check(DutyJournal.queue(newActive).single() == proof)
    DutyJournal.setQueue(newActive,BackgroundOrderAlertDuty.acknowledge(DutyJournal.queue(newActive),proof,true,proof.consent))
    check(DutyJournal.queue(newActive).isEmpty() && DutyJournal.scope(newActive)!!.consent == fresh.getString("consent_id"))
    check(newActive.getBoolean("enabled") && newActive.getString("status_secret") == fresh.getString("status_secret"))
    println("PASS encrypted-record payload survives cold JSON re-read as revoke-only, lost ACK retains identity, valid ACK admits fresh explicit consent")
}
