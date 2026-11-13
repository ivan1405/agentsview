<script lang="ts">
  import mark from "../../../assets/brand/parser-mark.svg";
  import { Modal } from "@kenn-io/kit-ui";
  import { m } from "../../i18n/index.js";
  import { sync } from "../../stores/sync.svelte.js";
  import { ui } from "../../stores/ui.svelte.js";

  const buildDate = $derived.by(() => {
    const raw = sync.serverVersion?.build_date;
    if (!raw) return null;
    try {
      return new Date(raw).toLocaleDateString(undefined, {
        year: "numeric",
        month: "long",
        day: "numeric",
        timeZone: "UTC",
      });
    } catch {
      return raw;
    }
  });
</script>

<Modal
  ariaLabel="Parser"
  closeLabel={m.about_close()}
  width="320px"
  onclose={() => (ui.activeModal = null)}
>
  <div class="about-header">
    <img class="about-logo" src={mark} width="40" height="40" alt="" />
    <div class="about-name">Parser</div>
  </div>

  <div class="about-body">
    <div class="about-row">
      <span class="about-label">{m.about_author()}</span>
      <span class="about-value">Kenn Software LLC</span>
    </div>
    {#if sync.serverVersion}
      <div class="about-row">
        <span class="about-label">{m.about_version()}</span>
        <span class="about-value mono">
          {sync.serverVersion.version}
        </span>
      </div>
      <div class="about-row">
        <span class="about-label">{m.about_commit()}</span>
        <span class="about-value mono">
          {sync.serverVersion.commit}
        </span>
      </div>
      {#if buildDate}
        <div class="about-row">
          <span class="about-label">{m.about_build_date()}</span>
          <span class="about-value">{buildDate}</span>
        </div>
      {/if}
    {/if}
  </div>

  <div class="about-footer">
    {m.about_footer()}
  </div>
</Modal>

<style>
  .about-header {
    display: flex;
    flex-direction: column;
    align-items: center;
    padding: 4px 4px 8px;
  }

  .about-logo {
    margin-bottom: 8px;
  }

  .about-name {
    font-size: 15px;
    font-weight: 650;
    color: var(--text-primary);
    letter-spacing: -0.01em;
  }

  .about-body {
    padding: 0 4px 8px;
  }

  .about-row {
    display: flex;
    justify-content: space-between;
    align-items: center;
    padding: 4px 0;
  }

  .about-label {
    font-size: 12px;
    color: var(--text-muted);
  }

  .about-value {
    font-size: 12px;
    color: var(--text-secondary);
  }

  .about-value.mono {
    font-family: var(--font-mono);
    font-size: 11px;
  }

  .about-footer {
    padding: 10px 4px 0;
    border-top: 1px solid var(--border-default);
    font-size: 11px;
    color: var(--text-muted);
    text-align: center;
  }
</style>
