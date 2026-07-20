import { apiClient } from './client'

export async function downloadBuild() {
  const blob = await apiClient.get<Blob>('/downloads/build', {
    responseType: 'blob',
  })

  // Cria um link temporário para download
  const url = window.URL.createObjectURL(blob)
  const link = document.createElement('a')
  link.href = url
  link.setAttribute('download', 'app-build.zip')
  document.body.appendChild(link)
  link.click()
  link.parentNode?.removeChild(link)
  window.URL.revokeObjectURL(url)
}
