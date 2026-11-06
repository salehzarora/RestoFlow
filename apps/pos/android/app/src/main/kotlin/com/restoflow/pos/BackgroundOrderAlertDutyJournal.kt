package com.restoflow.pos

import org.json.JSONArray
import org.json.JSONObject
import java.security.MessageDigest
import java.security.SecureRandom
import java.util.UUID

/** All fields are inside the existing Keystore-encrypted record, including the revoke-only queue. */
internal object DutyJournal {
    const val STAGED = "duty_staged"
    const val QUEUE = "duty_revokes"
    fun token(): String = ByteArray(32).also { SecureRandom().nextBytes(it) }.joinToString("") { "%02x".format(it.toInt() and 255) }
    fun hash(value: String): String = MessageDigest.getInstance("SHA-256").digest(value.toByteArray(Charsets.US_ASCII))
        .joinToString("") { "%02x".format(it.toInt() and 255) }

    fun stage(installation: String, identity: String, endpoint: String, boot: Int) = JSONObject()
        .put("installation_id", installation).put("identity", identity).put("endpoint", endpoint)
        .put("boot_count", boot).put("consent_id", UUID.randomUUID().toString()).put("revoke_secret", token())

    fun bind(staged: JSONObject, args: Map<*,*>, now: Long, old: JSONObject): JSONObject? {
        if (!staged.has("started_tick") || !staged.has("status_secret") ||
            staged.getString("installation_id") != args["installation_id"] || staged.getString("consent_id") != args["consent_id"] ||
            staged.getString("identity") != args["identity"] || staged.getString("endpoint") != args["endpoint"]) return null
        for (key in listOf("shift_id","registration_id","registration_generation","policy_revision")) {
            if (!BackgroundOrderAlertProtocol.uuid(args[key] as? String ?: return null)) return null
        }
        val rawEnd = args["authority_expires_at"] as? String ?: return null
        val end = BackgroundOrderAlertProtocol.timestamp(rawEnd) ?: return null
        val server = BackgroundOrderAlertProtocol.timestamp(args["server_time"] as? String ?: return null) ?: return null
        val remaining = BackgroundOrderAlertDuty.remaining(server,end,end,staged.getLong("started_tick"),now,null) ?: return null
        return JSONObject(staged.toString()).apply {
            for (key in listOf("shift_id","registration_id","registration_generation","policy_revision")) put(key,args[key])
            put("enabled",true).put("opt_in",true).put("duty_status_unknown",false).put("token_refresh_unconfirmed",false)
            put("duty_end",rawEnd).put("authority_deadline", now + remaining)
            remove("started_tick")
            setQueue(this,queue(old))
        }
    }

    fun proof(value: JSONObject) = BackgroundOrderAlertDuty.Revocation(
        value.getString("installation_id"), value.getString("consent_id"), value.getString("revoke_secret"))

    data class Snapshot(val values: Map<String,Long>, val serverNow: Long, val deadline: Long, val absoluteEnd: String)
    fun snapshot(raw: JSONObject, owner: DutyScope, record: JSONObject, started: Long, now: Long): Snapshot {
        check(BackgroundOrderAlertDuty.validReply(raw.opt("ok"),raw.opt("consent_id"),raw.opt("registration_id"),raw.opt("generation"),owner))
        val server = BackgroundOrderAlertProtocol.timestamp(raw.getString("server_time")) ?: error("invalid time")
        val rawEnd = raw.getString("authority_expires_at")
        val end = BackgroundOrderAlertProtocol.timestamp(rawEnd) ?: error("invalid time")
        val knownEnd = BackgroundOrderAlertProtocol.timestamp(record.getString("duty_end")) ?: error("invalid end")
        val remaining = BackgroundOrderAlertDuty.remaining(server,end,knownEnd,started,now,record.getLong("authority_deadline")) ?: error("expired")
        val array = raw.getJSONArray("requests")
        check(array.length() <= 50)
        val values = linkedMapOf<String,Long>()
        for (i in 0 until array.length()) {
            val item = array.getJSONObject(i)
            val id = item.getString("request_id")
            val expiry = BackgroundOrderAlertProtocol.timestamp(item.getString("expires_at")) ?: error("invalid time")
            check(BackgroundOrderAlertProtocol.uuid(id) && expiry > server && values.put(id,expiry) == null)
        }
        return Snapshot(values,server+(now-started),now+remaining,rawEnd)
    }

    fun queue(record: JSONObject): List<BackgroundOrderAlertDuty.Revocation> {
        val array = record.optJSONArray(QUEUE) ?: return emptyList()
        require(array.length() <= BackgroundOrderAlertDuty.MAX_PENDING_REVOKES)
        return (0 until array.length()).map { proof(array.getJSONObject(it)) }
    }

    fun setQueue(record: JSONObject, items: List<BackgroundOrderAlertDuty.Revocation>) {
        if (items.isEmpty()) { record.remove(QUEUE); return }
        val array = JSONArray()
        for (item in items) array.put(JSONObject().put("installation_id", item.installation)
            .put("consent_id", item.consent).put("revoke_secret", item.secret))
        record.put(QUEUE, array)
    }

    fun owns(record: JSONObject) = record.has("consent_id") || record.has(STAGED) || record.has(QUEUE)
    fun scope(record: JSONObject): DutyScope? = if (!record.has("consent_id")) null else DutyScope(
        record.getString("consent_id"), record.getString("installation_id"), record.getString("identity"),
        record.getString("shift_id"), record.getString("registration_id"), record.getString("registration_generation"),
        record.getString("policy_revision"))

    /** One replacement drops every general credential and preserves only the exact independent proofs. */
    fun stopped(record: JSONObject, retainOptIn: Boolean, expired: Boolean): JSONObject {
        var pending = queue(record)
        record.optJSONObject(STAGED)?.let {
            // A preview-only reservation cannot grant authority and expires on the server.
            if (BackgroundOrderAlertDuty.needsRevocation(false, it.has("started_tick")))
                pending = BackgroundOrderAlertDuty.enqueue(pending, proof(it))
        }
        if (record.has("consent_id")) pending = BackgroundOrderAlertDuty.enqueue(pending, proof(record))
        return JSONObject().also {
            if (record.has("installation_id")) it.put("installation_id", record.getString("installation_id"))
            if (retainOptIn && record.opt("opt_in") == true) it.put("opt_in", true)
            if (expired) it.put("duty_expired", true)
            setQueue(it, pending)
        }
    }
}
